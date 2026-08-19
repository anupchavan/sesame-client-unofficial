import Foundation
import AVFoundation
import WebRTC

/// One audio call over the agent's existing WebSocket: SDP/ICE signalling via JSON-RPC
/// frames, media over WebRTC.
@MainActor
final class CallManager: NSObject, ObservableObject {
    @Published var state: CallState = .none
    @Published var isMuted = false

    private weak var client: ChatClient?
    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var agent: Agent?
    private var callID: Any?
    private var answerApplied = false

    var isActive: Bool {
        if case .none = state { return false }
        if case .ended = state { return false }
        return true
    }

    func start(agent: Agent, client: ChatClient) async {
        guard !isActive else { return }
        guard await AudioRecorder.requestPermission() else {
            state = .ended("Microphone access denied")
            return
        }
        self.client = client
        self.agent = agent
        callID = nil
        answerApplied = false
        state = .connecting
        client.onCallFrame = { [weak self] method, content in
            self?.handleFrame(method: method, content: content)
        }

        RTCInitializeSSL()
        let factory = RTCPeerConnectionFactory()
        self.factory = factory

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = client.iceServers.compactMap { dict in
            var urls: [String] = []
            if let u = dict["urls"] as? [String] { urls = u }
            else if let u = dict["urls"] as? String { urls = [u] }
            else if let u = dict["url"] as? String { urls = [u] }
            guard !urls.isEmpty else { return nil }
            return RTCIceServer(urlStrings: urls,
                                username: dict["username"] as? String ?? "",
                                credential: dict["credential"] as? String ?? "")
        }

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            state = .ended("Could not create connection")
            return
        }
        self.peer = peer

        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = factory.audioTrack(with: source, trackId: "audio0")
        peer.add(track, streamIds: ["stream0"])
        audioTrack = track

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil)
        peer.offer(for: offerConstraints) { [weak self] sdp, error in
            Task { @MainActor in
                guard let self, let sdp else {
                    self?.end(reason: "offer failed: \(error?.localizedDescription ?? "?")")
                    return
                }
                // The answer can only be applied once the local description is committed,
                // so hold off signalling until then.
                self.peer?.setLocalDescription(sdp) { err in
                    Task { @MainActor in
                        if let err {
                            self.end(reason: "local sdp failed: \(err.localizedDescription)", notifyServer: false)
                        } else {
                            self.sendConnect(offerSDP: sdp.sdp)
                        }
                    }
                }
            }
        }
    }

    private func sendConnect(offerSDP: String) {
        guard let client, let agent else { return }
        client.notify("client.voice_state", content: ["voice": "connecting"])
        let content: [String: Any] = [
            "webrtc_offer_sdp": offerSDP,
            "sample_rate": 48000,
            "audio_codec": "opus",
            "supports_control_plane_reconnect": true,
            "reconnect": false,
            "is_private": false,
            "settings": ["character": agent.rawValue],
            "client_name": "iOS",
            "client_metadata": [
                "device_model": "Mac",
                "device_type": "desktop",
                "app_version": "2",
                "media_devices": [["kind": "audioinput", "label": "Built-in Microphone"]],
            ],
        ]
        Task {
            do {
                let result = try await client.request("call.connect", content: content)
                await MainActor.run { self.handleConnectResult(result) }
            } catch {
                await MainActor.run {
                    var reason = error.localizedDescription
                    if reason.contains("already has an active call") {
                        reason = "A previous call is still open server-side — try again in a moment"
                    }
                    self.end(reason: reason, notifyServer: false)
                }
            }
        }
        client.notify("webrtc.sdp.offer", content: ["sdp": offerSDP, "sample_rate": 48000])
        state = .ringing
    }

    private func handleConnectResult(_ result: [String: Any]) {
        callID = result["call_id"] ?? (result["content"] as? [String: Any])?["call_id"]
        let content = (result["content"] as? [String: Any]) ?? result
        for key in ["webrtc_answer_sdp", "answer_sdp", "sdp", "answer"] {
            if let sdp = content[key] as? String, sdp.contains("v=0") {
                applyAnswer(sdp)
                return
            }
        }
    }

    private func handleFrame(method: String, content: [String: Any]) {
        switch method {
        case "webrtc.sdp.answer", "webrtc.answer", "call.answer", "webrtc.sdp":
            if let sdp = (content["sdp"] as? String) ?? (content["answer_sdp"] as? String) {
                applyAnswer(sdp)
            }
        case "webrtc.ice_candidate", "webrtc.ice.candidate":
            let sdp = (content["sdp"] as? String) ?? (content["candidate"] as? String)
            guard let sdp else { return }
            let mid = content["sdp_mid"] as? String
            let idx = (content["sdp_m_line_index"] as? Int) ?? 0
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: mid)
            peer?.add(candidate) { _ in }
        case "call.disconnect", "call.ended", "call.end":
            end(reason: (content["reason"] as? String) ?? "Call ended", notifyServer: false)
        default:
            break
        }
    }

    private func applyAnswer(_ sdp: String) {
        // The answer arrives twice (pushed webrtc.sdp.answer + call.connect result) — apply once.
        guard !answerApplied else { return }
        answerApplied = true
        let answer = RTCSessionDescription(type: .answer, sdp: sdp)
        peer?.setRemoteDescription(answer) { [weak self] error in
            Task { @MainActor in
                if let error {
                    WSLog.log("call: setRemoteDescription failed: \(error.localizedDescription)", always: true)
                    self?.end(reason: "answer failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        audioTrack?.isEnabled = !isMuted
    }

    func end(reason: String? = nil, notifyServer: Bool = true) {
        if notifyServer {
            var content: [String: Any] = ["reason": "user_request"]
            if let callID { content["call_id"] = callID }
            client?.notify("call.disconnect", content: content)
        }
        callID = nil
        answerApplied = false
        client?.notify("client.voice_state", content: ["voice": "disconnected"])
        peer?.close()
        peer = nil
        audioTrack = nil
        factory = nil
        isMuted = false
        state = .ended(reason)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if case .ended = state { state = .none }
        }
    }
}

extension CallManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            self.client?.notify("webrtc.ice_candidate", content: [
                "sdp": candidate.sdp,
                "sdp_mid": candidate.sdpMid ?? "0",
                "sdp_m_line_index": Int(candidate.sdpMLineIndex),
            ])
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            switch newState {
            case .connected, .completed:
                if case .active = self.state {} else {
                    self.state = .active(since: Date())
                    self.client?.notify("client.voice_state", content: ["voice": "connected"])
                }
            case .failed:
                self.end(reason: "Connection lost")
            case .disconnected:
                break // often transient; ICE may recover
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
