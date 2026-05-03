//! Element Call (MatrixRTC + LiveKit) widget URL and [matrix_sdk::widget::WidgetDriver] bridge.

use language_tags::LanguageTag;
use matrix_sdk::{
    ruma::{
        api::client::discovery::discover_homeserver::RtcFocusInfo,
        events::{MessageLikeEventType, StateEventType},
    },
    widget::{
        Capabilities, CapabilitiesProvider, ClientProperties, EncryptionSystem, Filter, Intent,
        MessageLikeEventFilter, StateEventFilter, ToDeviceEventFilter,
        VirtualElementCallWidgetConfig, VirtualElementCallWidgetProperties, WidgetDriver,
        WidgetSettings,
    },
    Client, Room,
};

/// Build Element Call widget capabilities (same rules as matrix-sdk-ffi `get_element_call_required_permissions`).
pub fn element_call_capabilities(own_user_id: &str, own_device_id: &str) -> Capabilities {
    let read_send = vec![
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            "org.matrix.rageshake_request".into(),
        )),
        Filter::ToDevice(ToDeviceEventFilter {
            event_type: "io.element.call.encryption_keys".into(),
        }),
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            "io.element.call.encryption_keys".into(),
        )),
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            "io.element.call.reaction".into(),
        )),
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            MessageLikeEventType::Reaction.to_string().into(),
        )),
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            MessageLikeEventType::RoomRedaction.to_string().into(),
        )),
        Filter::MessageLike(MessageLikeEventFilter::WithType(
            MessageLikeEventType::RtcDecline.to_string().into(),
        )),
    ];

    Capabilities {
        read: vec![
            Filter::State(StateEventFilter::WithType(StateEventType::CallMember.to_string().into())),
            Filter::State(StateEventFilter::WithType(StateEventType::RoomName.to_string().into())),
            Filter::State(StateEventFilter::WithType(StateEventType::RoomMember.to_string().into())),
            Filter::State(StateEventFilter::WithType(
                StateEventType::RoomEncryption.to_string().into(),
            )),
            Filter::State(StateEventFilter::WithType(
                StateEventType::RoomCreate.to_string().into(),
            )),
        ]
        .into_iter()
        .chain(read_send.clone())
        .collect(),
        send: vec![
            Filter::MessageLike(MessageLikeEventFilter::WithType(
                MessageLikeEventType::RtcNotification.to_string().into(),
            )),
            Filter::MessageLike(MessageLikeEventFilter::WithType(
                MessageLikeEventType::CallNotify.to_string().into(),
            )),
            Filter::State(StateEventFilter::WithTypeAndStateKey(
                StateEventType::CallMember.to_string().into(),
                own_user_id.to_owned(),
            )),
            Filter::State(StateEventFilter::WithTypeAndStateKey(
                StateEventType::CallMember.to_string().into(),
                format!("{own_user_id}_{own_device_id}"),
            )),
            Filter::State(StateEventFilter::WithTypeAndStateKey(
                StateEventType::CallMember.to_string().into(),
                format!("{own_user_id}_{own_device_id}_m.call"),
            )),
            Filter::State(StateEventFilter::WithTypeAndStateKey(
                StateEventType::CallMember.to_string().into(),
                format!("_{own_user_id}_{own_device_id}"),
            )),
            Filter::State(StateEventFilter::WithTypeAndStateKey(
                StateEventType::CallMember.to_string().into(),
                format!("_{own_user_id}_{own_device_id}_m.call"),
            )),
        ]
        .into_iter()
        .chain(read_send)
        .collect(),
        requires_client: true,
        update_delayed_event: true,
        send_delayed_event: true,
    }
}

#[derive(Clone)]
struct AlwaysGrantElementCallCaps {
    caps: Capabilities,
}

impl CapabilitiesProvider for AlwaysGrantElementCallCaps {
    async fn acquire_capabilities(
        &self,
        _requested: Capabilities,
    ) -> Capabilities {
        self.caps.clone()
    }
}

fn pick_intent(is_dm: bool, join_existing: bool, voice_only: bool) -> Intent {
    match (is_dm, join_existing, voice_only) {
        (true, true, true) => Intent::JoinExistingDmVoice,
        (true, true, false) => Intent::JoinExistingDm,
        (true, false, true) => Intent::StartCallDmVoice,
        (true, false, false) => Intent::StartCallDm,
        (false, true, _) => Intent::JoinExisting,
        (false, false, _) => Intent::StartCall,
    }
}

fn build_widget_settings(
    element_call_base_url: &str,
    intent: Intent,
    widget_id: &str,
) -> Result<WidgetSettings, url::ParseError> {
    let props = VirtualElementCallWidgetProperties {
        element_call_url: element_call_base_url.trim_end_matches('/').to_owned(),
        widget_id: widget_id.to_owned(),
        encryption: EncryptionSystem::PerParticipantKeys,
        ..Default::default()
    };
    let mut config = VirtualElementCallWidgetConfig::default();
    config.intent = Some(intent);
    config.confine_to_room = Some(true);
    WidgetSettings::new_virtual_element_call_widget(props, config)
}

/// Generate the WebView URL only (no widget driver). Each call uses a new random widget id.
pub async fn element_call_webview_url(
    room: &Room,
    element_call_base_url: &str,
    widget_id: &str,
    is_dm: bool,
    join_existing_call: bool,
    voice_only: bool,
    client_id: &str,
    language_tag: Option<&str>,
    theme: Option<&str>,
) -> Result<String, String> {
    let intent = pick_intent(is_dm, join_existing_call, voice_only);
    let settings =
        build_widget_settings(element_call_base_url, intent, widget_id).map_err(|e| e.to_string())?;
    let lang = language_tag.and_then(|s| LanguageTag::parse(s).ok());
    let props = ClientProperties::new(client_id, lang, theme.map(|s| s.to_owned()));
    let url = WidgetSettings::generate_webview_url(&settings, room, props)
        .await
        .map_err(|e| e.to_string())?;
    Ok(url.to_string())
}

pub async fn rtc_foci_livekit_service_urls(client: &Client) -> Result<Vec<String>, String> {
    let foci = client.rtc_foci().await.map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for f in foci {
        if let RtcFocusInfo::LiveKit(lk) = f {
            out.push(lk.service_url.clone());
        }
    }
    Ok(out)
}

/// Start widget driver + forward loop. Returns `(driver_join, forward_join, handle)`.
pub async fn start_element_call_widget_session(
    room: Room,
    element_call_base_url: &str,
    widget_id: &str,
    is_dm: bool,
    join_existing_call: bool,
    voice_only: bool,
    _client_id: &str,
    _language_tag: Option<&str>,
    _theme: Option<&str>,
    own_user_id: &str,
    own_device_id: &str,
    to_widget: crate::frb_generated::StreamSink<String>,
) -> Result<
    (
        tokio::task::JoinHandle<()>,
        tokio::task::JoinHandle<()>,
        matrix_sdk::widget::WidgetDriverHandle,
    ),
    String,
> {
    let intent = pick_intent(is_dm, join_existing_call, voice_only);
    let settings =
        build_widget_settings(element_call_base_url, intent, widget_id).map_err(|e| e.to_string())?;

    let (driver, handle) = WidgetDriver::new(settings);
    let caps = AlwaysGrantElementCallCaps {
        caps: element_call_capabilities(own_user_id, own_device_id),
    };
    let handle_for_forward = handle.clone();
    let forward = tokio::spawn(async move {
        loop {
            match handle_for_forward.recv().await {
                Some(msg) => {
                    if to_widget.add(msg).is_err() {
                        break;
                    }
                }
                None => break,
            }
        }
    });

    let driver_join = tokio::spawn(async move {
        let _ = driver.run(room, caps).await;
    });

    Ok((driver_join, forward, handle))
}
