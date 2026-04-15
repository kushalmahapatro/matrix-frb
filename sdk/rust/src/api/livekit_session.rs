//! LiveKit room session using the Rust [`livekit`] crate (libwebrtc), exposed to Flutter via FRB.
//!
//! **Local media** is fed from Flutter: PCM16 from the `record` plugin into [`livekit_session_push_audio_pcm16`],
//! and tightly packed I420 from the `camera` preview into [`livekit_session_push_video_i420`].
//!
//! **First remote microphone** is decoded in Rust via [`NativeAudioStream`], pushed into a bounded ring buffer,
//! and consumed by Flutter through [`livekit_session_pull_remote_audio_pcm16`] (see app `flutter_sound` downlink).

#[cfg(target_arch = "wasm32")]
pub mod imp {
    pub async fn livekit_session_connect(
        _url: String,
        _token: String,
        _voice_only: bool,
    ) -> Result<(), String> {
        Err("LiveKit native session is not available on web.".to_owned())
    }

    pub async fn livekit_session_close() -> Result<(), String> {
        Err("No LiveKit session.".to_owned())
    }

    pub async fn livekit_session_connection_state() -> String {
        "unsupported".to_owned()
    }

    pub async fn livekit_session_push_audio_pcm16(
        _pcm: Vec<i16>,
        _sample_rate: u32,
        _num_channels: u32,
    ) -> Result<(), String> {
        Err("LiveKit not available on web.".to_owned())
    }

    pub async fn livekit_session_push_video_i420(
        _width: u32,
        _height: u32,
        _data: Vec<u8>,
        _timestamp_us: i64,
        _rotation_degrees: i32,
    ) -> Result<(), String> {
        Err("LiveKit not available on web.".to_owned())
    }

    pub async fn livekit_session_remote_participant_count() -> i32 {
        0
    }

    pub async fn livekit_session_set_microphone_muted(_muted: bool) -> Result<(), String> {
        Err("LiveKit not available on web.".to_owned())
    }

    pub async fn livekit_session_set_camera_muted(_muted: bool) -> Result<(), String> {
        Err("LiveKit not available on web.".to_owned())
    }

    pub async fn livekit_session_publish_local_camera_track() -> Result<(), String> {
        Err("LiveKit native session is not available on web.".to_owned())
    }

    pub async fn livekit_session_pull_remote_audio_pcm16(_max_samples: usize) -> Vec<i16> {
        Vec::new()
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub mod imp {
    use std::borrow::Cow;
    use std::collections::{HashSet, VecDeque};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;
    use std::sync::LazyLock;

    use futures_util::StreamExt;
    use livekit::options::TrackPublishOptions;
    use livekit::prelude::*;
    use livekit::track::{LocalAudioTrack, LocalTrack, LocalVideoTrack};
    use livekit::webrtc::audio_source::native::NativeAudioSource;
    use livekit::webrtc::audio_source::AudioSourceOptions;
    use livekit::webrtc::audio_stream::native::NativeAudioStream;
    use livekit::webrtc::prelude::{AudioFrame, RtcAudioSource, RtcVideoSource, VideoRotation};
    use livekit::webrtc::video_frame::{I420Buffer, VideoFrame};
    use livekit::webrtc::video_source::native::NativeVideoSource;
    use livekit::webrtc::video_source::VideoResolution;
    use livekit::webrtc::video_stream::native::NativeVideoStream;
    use tokio::sync::Mutex;
    use tokio::task::JoinHandle;
    use tokio_util::sync::CancellationToken;

    struct LiveKitHeld {
        room: Arc<Room>,
        audio_source: NativeAudioSource,
        /// Pending PCM samples before forming 10 ms WebRTC frames (see `NativeAudioSource` docs).
        audio_buffer: Vec<i16>,
        video_source: Option<NativeVideoSource>,
        _drain_events: JoinHandle<()>,
        /// Remote track attach loop (video drain + first-remote audio ring buffer).
        _remote_media_playout: JoinHandle<()>,
        /// Mono i16 @ 48 kHz from the first remote mic (`NativeAudioStream`); Flutter pulls and plays.
        remote_pcm_ring: Arc<Mutex<VecDeque<i16>>>,
        remote_play_cancel: CancellationToken,
    }

    static SESSION: LazyLock<Mutex<Option<LiveKitHeld>>> = LazyLock::new(|| Mutex::new(None));

    /// Flutter → Rust FRB calls carrying PCM batches (see [livekit_session_push_audio_pcm16]).
    static LIVEKIT_AUDIO_PCM_BATCHES_FROM_FLUTTER: AtomicU64 = AtomicU64::new(0);
    /// Successful [NativeAudioSource::capture_frame] calls (10 ms frames into libwebrtc).
    static LIVEKIT_AUDIO_WEBRTC_FRAMES_OUT: AtomicU64 = AtomicU64::new(0);

    /// WebRTC `InitAndroid` must run on the **Android main thread** (see `WebRtcAndroidInit` in Kotlin).
    /// Running it from this async path (`tokio`) breaks JNI class lookup (`JniInit` not found).
    #[cfg(target_os = "android")]
    fn ensure_webrtc_android_ready_for_connect() -> Result<(), String> {
        if crate::android_init::webrtc_android_initialized() {
            Ok(())
        } else {
            Err(
                "WebRTC Android was not initialized on the main thread. Call WebRtcAndroidInit.init() in MainActivity after super.onCreate().".into(),
            )
        }
    }

    #[cfg(not(target_os = "android"))]
    fn ensure_webrtc_android_ready_for_connect() -> Result<(), String> {
        Ok(())
    }

    const AUDIO_SAMPLE_RATE: u32 = 48_000;
    const AUDIO_CHANNELS: u32 = 1;
    /// 10 ms at 48 kHz mono.
    const AUDIO_SAMPLES_10MS: usize = (AUDIO_SAMPLE_RATE / 100) as usize;
    /// Drop audio if Flutter gets this far ahead (about 200 ms).
    const AUDIO_BUFFER_CAP_SAMPLES: usize = AUDIO_SAMPLES_10MS * 20;
    /// ~3 s of mono 48 kHz remote PCM; overflow drops oldest samples to cap latency.
    const REMOTE_PCM_RING_CAP_SAMPLES: usize = AUDIO_SAMPLE_RATE as usize * 3;

    async fn push_i16_to_remote_ring(ring: &Mutex<VecDeque<i16>>, data: &[i16]) {
        let mut q = ring.lock().await;
        for &s in data {
            while q.len() >= REMOTE_PCM_RING_CAP_SAMPLES {
                q.pop_front();
            }
            q.push_back(s);
        }
    }

    fn map_rotation(deg: i32) -> VideoRotation {
        let d = ((deg % 360) + 360) % 360;
        match d {
            90 => VideoRotation::VideoRotation90,
            180 => VideoRotation::VideoRotation180,
            270 => VideoRotation::VideoRotation270,
            _ => VideoRotation::VideoRotation0,
        }
    }

    fn expected_i420_len(width: u32, height: u32) -> usize {
        let cw = ((width + 1) / 2) as usize;
        let ch = ((height + 1) / 2) as usize;
        (width as usize) * (height as usize) + 2 * cw * ch
    }

    /// Copy tightly packed I420 (Y, then U, then V) into a new buffer and push to the video source.
    fn push_i420_tight(
        video: &NativeVideoSource,
        width: u32,
        height: u32,
        data: &[u8],
        timestamp_us: i64,
        rotation: VideoRotation,
    ) -> Result<(), String> {
        let expected = expected_i420_len(width, height);
        if data.len() != expected {
            return Err(format!(
                "I420 size mismatch: got {} want {} ({}x{})",
                data.len(),
                expected,
                width,
                height
            ));
        }

        let mut buffer = I420Buffer::new(width, height);
        let (stride_y, stride_u, stride_v) = buffer.strides();
        let (y_dst, u_dst, v_dst) = buffer.data_mut();

        let cw = ((width + 1) / 2) as usize;
        let ch = ((height + 1) / 2) as usize;
        let y_size = (width as usize) * (height as usize);

        // Y plane
        for row in 0..height as usize {
            let src = row * (width as usize);
            let dst = row * (stride_y as usize);
            y_dst[dst..dst + width as usize].copy_from_slice(&data[src..src + width as usize]);
        }

        // U then V (tight layout in `data` after Y)
        let mut off = y_size;
        for row in 0..ch {
            let dst = row * (stride_u as usize);
            u_dst[dst..dst + cw].copy_from_slice(&data[off..off + cw]);
            off += cw;
        }
        for row in 0..ch {
            let dst = row * (stride_v as usize);
            v_dst[dst..dst + cw].copy_from_slice(&data[off..off + cw]);
            off += cw;
        }

        let frame = VideoFrame {
            rotation,
            timestamp_us,
            buffer,
        };
        video.capture_frame(&frame);
        Ok(())
    }

    fn set_local_track_muted(room: &Room, source: TrackSource, muted: bool) -> Result<(), String> {
        let lp = room.local_participant();
        for pub_ in lp.track_publications().values() {
            if pub_.source() == source {
                if muted {
                    pub_.mute();
                } else {
                    pub_.unmute();
                }
                return Ok(());
            }
        }
        if source == TrackSource::Camera {
            return Ok(());
        }
        Err(format!("No local {:?} track published.", source))
    }

    async fn dispose_held(held: LiveKitHeld) -> Result<(), String> {
        held.remote_play_cancel.cancel();
        held._remote_media_playout.abort();
        let close_res = held.room.close().await.map_err(|e| e.to_string());
        held._drain_events.abort();
        close_res
    }

    /// [`RemoteTrackPublication::is_subscribed`] is `track().is_some()` (misnamed); use
    /// [`RemoteTrackPublication::is_desired`] to detect missing SFU subscription.
    fn ensure_remote_publication_desired(publication: &RemoteTrackPublication) {
        if !publication.is_desired() {
            publication.set_subscribed(true);
        }
    }

    /// For each remote **video** track, drain decoded frames. First remote **audio** is drained into
    /// [LiveKitHeld::remote_pcm_ring] for Flutter playback; additional remote mics use default playout.
    fn attach_remote_tracks_from_participant(
        attached: &mut HashSet<TrackSid>,
        first_remote_audio_drain: &mut Option<TrackSid>,
        ring: &Arc<Mutex<VecDeque<i16>>>,
        play_cancel: &CancellationToken,
        participant: &RemoteParticipant,
    ) {
        for pub_ in participant.track_publications().values() {
            ensure_remote_publication_desired(pub_);
            if let Some(track) = pub_.track() {
                attach_remote_track_if_new(
                    attached,
                    first_remote_audio_drain,
                    ring,
                    play_cancel,
                    track,
                );
            }
        }
    }

    fn spawn_remote_media_playout_task(
        room: Arc<Room>,
        ring: Arc<Mutex<VecDeque<i16>>>,
        play_cancel: CancellationToken,
    ) -> JoinHandle<()> {
        tokio::spawn(async move {
            let mut rx = room.subscribe();
            let mut attached: HashSet<TrackSid> = HashSet::new();
            let mut first_remote_audio_drain: Option<TrackSid> = None;

            // `RoomEvent::Connected` is dispatched *during* `Room::connect` before this task
            // subscribes, so we often miss it. Catch up on any remote tracks that already exist.
            for p in room.remote_participants().values() {
                attach_remote_tracks_from_participant(
                    &mut attached,
                    &mut first_remote_audio_drain,
                    &ring,
                    &play_cancel,
                    p,
                );
            }
            if !attached.is_empty() {
                tracing::info!(
                    target: "matrix_livekit_audio",
                    remote_tracks_attached = attached.len(),
                    "remote media playout: catch-up attached existing participant track(s)"
                );
            }

            loop {
                tokio::select! {
                    _ = play_cancel.cancelled() => break,
                    maybe_ev = rx.recv() => {
                        let Some(event) = maybe_ev else { break };
                        match event {
                            RoomEvent::Connected {
                                participants_with_tracks,
                            } => {
                                for (_participant, pubs) in participants_with_tracks {
                                    for publication in pubs {
                                        ensure_remote_publication_desired(&publication);
                                        if let Some(track) = publication.track() {
                                            attach_remote_track_if_new(
                                                &mut attached,
                                                &mut first_remote_audio_drain,
                                                &ring,
                                                &play_cancel,
                                                track,
                                            );
                                        }
                                    }
                                }
                            }
                            RoomEvent::ParticipantConnected(p) => {
                                attach_remote_tracks_from_participant(
                                    &mut attached,
                                    &mut first_remote_audio_drain,
                                    &ring,
                                    &play_cancel,
                                    &p,
                                );
                            }
                            RoomEvent::ParticipantActive(p) => {
                                attach_remote_tracks_from_participant(
                                    &mut attached,
                                    &mut first_remote_audio_drain,
                                    &ring,
                                    &play_cancel,
                                    &p,
                                );
                            }
                            RoomEvent::TrackPublished { publication, .. } => {
                                ensure_remote_publication_desired(&publication);
                                if let Some(track) = publication.track() {
                                    attach_remote_track_if_new(
                                        &mut attached,
                                        &mut first_remote_audio_drain,
                                        &ring,
                                        &play_cancel,
                                        track,
                                    );
                                }
                            }
                            RoomEvent::TrackSubscribed {
                                track, publication, ..
                            } => {
                                ensure_remote_publication_desired(&publication);
                                attach_remote_track_if_new(
                                    &mut attached,
                                    &mut first_remote_audio_drain,
                                    &ring,
                                    &play_cancel,
                                    track,
                                );
                            }
                            RoomEvent::Disconnected { .. } => break,
                            _ => {}
                        }
                    }
                }
            }
        })
    }

    fn attach_remote_track_if_new(
        attached: &mut HashSet<TrackSid>,
        first_remote_audio_drain: &mut Option<TrackSid>,
        ring: &Arc<Mutex<VecDeque<i16>>>,
        play_cancel: &CancellationToken,
        track: RemoteTrack,
    ) {
        match track {
            RemoteTrack::Audio(audio) => {
                let sid = audio.sid();
                if !attached.insert(sid.clone()) {
                    return;
                }
                let drain_to_flutter = first_remote_audio_drain.is_none();
                if drain_to_flutter {
                    *first_remote_audio_drain = Some(sid.clone());
                }
                audio.enable();
                if drain_to_flutter {
                    let ring = ring.clone();
                    let child = play_cancel.child_token();
                    tokio::spawn(async move {
                        let rtc = audio.rtc_track();
                        let mut stream = NativeAudioStream::new(
                            rtc,
                            AUDIO_SAMPLE_RATE as i32,
                            AUDIO_CHANNELS as i32,
                        );
                        loop {
                            tokio::select! {
                                _ = child.cancelled() => break,
                                frame = stream.next() => {
                                    match frame {
                                        None => break,
                                        Some(f) => {
                                            push_i16_to_remote_ring(&ring, f.data.as_ref()).await;
                                        }
                                    }
                                }
                            }
                        }
                    });
                    tracing::info!(
                        target: "matrix_livekit_audio",
                        track_sid = ?sid,
                        "remote audio: NativeAudioStream → Flutter pull ring (first remote mic)"
                    );
                } else {
                    tracing::info!(
                        target: "matrix_livekit_audio",
                        track_sid = ?sid,
                        enabled = audio.is_enabled(),
                        "remote audio: extra participant, default WebRTC playout only"
                    );
                }
            }
            RemoteTrack::Video(video) => {
                let sid = video.sid();
                if !attached.insert(sid) {
                    return;
                }
                spawn_remote_video_stream_consumer(video);
            }
        }
    }

    fn spawn_remote_video_stream_consumer(video: RemoteVideoTrack) {
        tokio::spawn(async move {
            let rtc = video.rtc_track();
            let mut stream = NativeVideoStream::new(rtc);
            while let Some(_frame) = stream.next().await {}
        });
    }

    async fn flush_audio(held: &mut LiveKitHeld) -> Result<(), String> {
        let frame_samples = AUDIO_SAMPLES_10MS * AUDIO_CHANNELS as usize;
        while held.audio_buffer.len() >= frame_samples {
            let chunk: Vec<i16> = held.audio_buffer.drain(..frame_samples).collect();
            let frame = AudioFrame {
                data: Cow::Owned(chunk),
                sample_rate: AUDIO_SAMPLE_RATE,
                num_channels: AUDIO_CHANNELS,
                samples_per_channel: AUDIO_SAMPLES_10MS as u32,
            };
            held.audio_source
                .capture_frame(&frame)
                .await
                .map_err(|e| e.to_string())?;
            LIVEKIT_AUDIO_WEBRTC_FRAMES_OUT.fetch_add(1, Ordering::Relaxed);
        }
        Ok(())
    }

    pub async fn livekit_session_connect(
        url: String,
        token: String,
        voice_only: bool,
    ) -> Result<(), String> {
        ensure_webrtc_android_ready_for_connect()?;
        let mut guard = SESSION.lock().await;
        // Tear-down races or a failed [livekit_session_close] can leave a stale session.
        // Always replace: close any existing room, then connect (fixes "already active" after hang-up).
        if let Some(held) = guard.take() {
            let _ = dispose_held(held).await;
        }
        LIVEKIT_AUDIO_PCM_BATCHES_FROM_FLUTTER.store(0, Ordering::Relaxed);
        LIVEKIT_AUDIO_WEBRTC_FRAMES_OUT.store(0, Ordering::Relaxed);

        #[allow(deprecated)]
        let options = RoomOptions::default();
        // Keep LiveKit default `single_peer_connection: false`. Forcing a single PC has been
        // linked to missing or unstable **remote audio playout** with custom local PCM injection
        // on some iOS/Android stacks; dual transceiver mode matches typical mobile LiveKit clients.
        let (room, mut events) = Room::connect(&url, &token, options)
            .await
            .map_err(|e| e.to_string())?;
        let room = Arc::new(room);

        let remote_pcm_ring = Arc::new(Mutex::new(VecDeque::new()));
        let remote_play_cancel = CancellationToken::new();
        let remote_media = spawn_remote_media_playout_task(
            room.clone(),
            remote_pcm_ring.clone(),
            remote_play_cancel.clone(),
        );

        let drain = tokio::spawn(async move { while events.recv().await.is_some() {} });

        // Flutter should feed dry PCM16 (see app `RecordConfig` on mobile). First remote mic is
        // drained in Rust and pulled from Dart (see [livekit_session_pull_remote_audio_pcm16]).
        let audio_source = NativeAudioSource::new(
            AudioSourceOptions {
                echo_cancellation: true,
                noise_suppression: true,
                auto_gain_control: true,
            },
            AUDIO_SAMPLE_RATE,
            AUDIO_CHANNELS,
            0,
        );
        let audio_track = LocalAudioTrack::create_audio_track(
            "microphone",
            RtcAudioSource::Native(audio_source.clone()),
        );
        let mut audio_opts = TrackPublishOptions::default();
        audio_opts.source = TrackSource::Microphone;
        // Default TrackPublishOptions uses Opus DTX (discontinuous transmission). With a custom
        // PCM source, VAD/DTX can classify the stream as "silent" and stop sending RTP for long
        // stretches — callers hear nothing. Prefer continuous encoding for voice calls.
        audio_opts.dtx = false;
        // RED + odd SFU / client mixes occasionally yield silent decode; keep uplink conservative.
        audio_opts.red = false;
        // Voice uplink: SPEECH Opus preset (typical VoIP). MUSIC (48k) is the generic default but
        // is a worse match for mono mic PCM in some SFU / client combinations.
        audio_opts.audio_encoding = Some(livekit::options::audio::SPEECH.encoding);
        let mic_publication = room
            .local_participant()
            .publish_track(LocalTrack::Audio(audio_track), audio_opts)
            .await
            .map_err(|e| e.to_string())?;
        // Ensure the server + WebRTC stack treat the mic as live (some joins start muted).
        mic_publication.unmute();

        let video_source = if voice_only {
            None
        } else {
            let vs = NativeVideoSource::new(
                VideoResolution {
                    width: 640,
                    height: 480,
                },
                false,
            );
            let video_track =
                LocalVideoTrack::create_video_track("camera", RtcVideoSource::Native(vs.clone()));
            let mut video_opts = TrackPublishOptions::default();
            video_opts.source = TrackSource::Camera;
            room.local_participant()
                .publish_track(LocalTrack::Video(video_track), video_opts)
                .await
                .map_err(|e| e.to_string())?;
            Some(vs)
        };

        *guard = Some(LiveKitHeld {
            room: room.clone(),
            audio_source,
            audio_buffer: Vec::with_capacity(AUDIO_SAMPLES_10MS * 4),
            video_source,
            _drain_events: drain,
            _remote_media_playout: remote_media,
            remote_pcm_ring,
            remote_play_cancel,
        });
        Ok(())
    }

    pub async fn livekit_session_close() -> Result<(), String> {
        let mut guard = SESSION.lock().await;
        let held = guard
            .take()
            .ok_or_else(|| "No active LiveKit session.".to_owned())?;
        let res = dispose_held(held).await;
        if cfg!(debug_assertions) {
            let g = SESSION.lock().await;
            debug_assert!(
                g.is_none(),
                "livekit_session_close: SESSION should be empty after close"
            );
        }
        res
    }

    pub async fn livekit_session_connection_state() -> String {
        let guard = SESSION.lock().await;
        let Some(h) = guard.as_ref() else {
            return "idle".to_owned();
        };
        format!("{:?}", h.room.connection_state())
    }

    pub async fn livekit_session_remote_participant_count() -> i32 {
        let guard = SESSION.lock().await;
        let Some(h) = guard.as_ref() else {
            return 0;
        };
        h.room.remote_participants().len() as i32
    }

    pub async fn livekit_session_set_microphone_muted(muted: bool) -> Result<(), String> {
        let guard = SESSION.lock().await;
        let Some(ref held) = *guard else {
            return Err("No active LiveKit session.".to_owned());
        };
        set_local_track_muted(&held.room, TrackSource::Microphone, muted)
    }

    pub async fn livekit_session_set_camera_muted(muted: bool) -> Result<(), String> {
        let guard = SESSION.lock().await;
        let Some(ref held) = *guard else {
            return Err("No active LiveKit session.".to_owned());
        };
        set_local_track_muted(&held.room, TrackSource::Camera, muted)
    }

    /// Publish a local camera track for sessions that connected with `voice_only: true`, so Flutter
    /// can push I420 frames after the user turns the camera on.
    pub async fn livekit_session_publish_local_camera_track() -> Result<(), String> {
        let mut guard = SESSION.lock().await;
        let Some(ref mut held) = *guard else {
            return Err("No active LiveKit session.".to_owned());
        };
        if held.video_source.is_some() {
            return Ok(());
        }

        let room = held.room.clone();
        let vs = NativeVideoSource::new(
            VideoResolution {
                width: 640,
                height: 480,
            },
            false,
        );
        let video_track =
            LocalVideoTrack::create_video_track("camera", RtcVideoSource::Native(vs.clone()));
        let mut video_opts = TrackPublishOptions::default();
        video_opts.source = TrackSource::Camera;
        room.local_participant()
            .publish_track(LocalTrack::Video(video_track), video_opts)
            .await
            .map_err(|e| e.to_string())?;
        held.video_source = Some(vs);
        Ok(())
    }

    pub async fn livekit_session_push_audio_pcm16(
        pcm: Vec<i16>,
        sample_rate: u32,
        num_channels: u32,
    ) -> Result<(), String> {
        if pcm.is_empty() {
            return Ok(());
        }
        if sample_rate != AUDIO_SAMPLE_RATE || num_channels != AUDIO_CHANNELS {
            return Err(format!(
                "Expected {} Hz / {} channel(s); got {} / {}",
                AUDIO_SAMPLE_RATE, AUDIO_CHANNELS, sample_rate, num_channels
            ));
        }

        let mut guard = SESSION.lock().await;
        let Some(ref mut held) = *guard else {
            return Err("No active LiveKit session.".to_owned());
        };

        held.audio_buffer.extend_from_slice(&pcm);
        if held.audio_buffer.len() > AUDIO_BUFFER_CAP_SAMPLES {
            let drop = held.audio_buffer.len() - AUDIO_BUFFER_CAP_SAMPLES;
            held.audio_buffer.drain(..drop);
        }
        let out = flush_audio(held).await;
        if out.is_ok() {
            let n = LIVEKIT_AUDIO_PCM_BATCHES_FROM_FLUTTER.fetch_add(1, Ordering::Relaxed) + 1;
            if n == 1 || n % 50 == 0 {
                let frames = LIVEKIT_AUDIO_WEBRTC_FRAMES_OUT.load(Ordering::Relaxed);
                tracing::info!(
                    target: "matrix_livekit_audio",
                    flutter_pcm_batches = n,
                    webrtc_capture_frames = frames,
                    "LiveKit uplink: PCM batches from Flutter; frames handed to WebRTC (RTP is encoded downstream)"
                );
            }
        }
        out
    }

    pub async fn livekit_session_push_video_i420(
        width: u32,
        height: u32,
        data: Vec<u8>,
        timestamp_us: i64,
        rotation_degrees: i32,
    ) -> Result<(), String> {
        let guard = SESSION.lock().await;
        let Some(ref held) = *guard else {
            return Err("No active LiveKit session.".to_owned());
        };
        let Some(ref video) = held.video_source else {
            return Ok(());
        };
        push_i420_tight(
            video,
            width,
            height,
            &data,
            timestamp_us,
            map_rotation(rotation_degrees),
        )
    }

    /// Pops up to [max_samples] mono PCM16 @ 48 kHz from the first remote microphone ring buffer.
    pub async fn livekit_session_pull_remote_audio_pcm16(max_samples: usize) -> Vec<i16> {
        if max_samples == 0 {
            return Vec::new();
        }
        let guard = SESSION.lock().await;
        let Some(ref held) = *guard else {
            return Vec::new();
        };
        let mut q = held.remote_pcm_ring.lock().await;
        let take = max_samples.min(q.len());
        if take == 0 {
            return Vec::new();
        }
        q.drain(0..take).collect()
    }
}

pub use imp::livekit_session_close;
pub use imp::livekit_session_connect;
pub use imp::livekit_session_connection_state;
pub use imp::livekit_session_publish_local_camera_track;
pub use imp::livekit_session_pull_remote_audio_pcm16;
pub use imp::livekit_session_push_audio_pcm16;
pub use imp::livekit_session_push_video_i420;
pub use imp::livekit_session_remote_participant_count;
pub use imp::livekit_session_set_camera_muted;
pub use imp::livekit_session_set_microphone_muted;
