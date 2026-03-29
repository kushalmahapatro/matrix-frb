#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
// EXTRA BEGIN
typedef struct DartCObject *WireSyncRust2DartDco;
typedef struct WireSyncRust2DartSse {
  uint8_t *ptr;
  int32_t len;
} WireSyncRust2DartSse;

typedef int64_t DartPort;
typedef bool (*DartPostCObjectFnType)(DartPort port_id, void *message);
void store_dart_post_cobject(DartPostCObjectFnType ptr);
// EXTRA END
typedef struct _Dart_Handle* Dart_Handle;



typedef struct wire_cst_list_prim_u_8_strict {
  uint8_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_8_strict;

typedef struct wire_cst_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate {
  uintptr_t *ptr;
  int32_t len;
} wire_cst_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate;

typedef struct wire_cst_client_config {
  struct wire_cst_list_prim_u_8_strict *session_path;
  struct wire_cst_list_prim_u_8_strict *homeserver_url;
  struct wire_cst_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate *root_certificates;
  struct wire_cst_list_prim_u_8_strict *proxy;
  struct wire_cst_list_prim_u_8_strict *passphrase;
  bool show_home_server_for_username;
  struct wire_cst_list_prim_u_8_strict *media_cache_path;
} wire_cst_client_config;

typedef struct wire_cst_list_String {
  struct wire_cst_list_prim_u_8_strict **ptr;
  int32_t len;
} wire_cst_list_String;

typedef struct wire_cst_list_prim_f_32_strict {
  float *ptr;
  int32_t len;
} wire_cst_list_prim_f_32_strict;

typedef struct wire_cst_list_prim_u_8_loose {
  uint8_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_8_loose;

typedef struct wire_cst_list_trace_log_packs {
  int32_t *ptr;
  int32_t len;
} wire_cst_list_trace_log_packs;

typedef struct wire_cst_tracing_file_configuration {
  struct wire_cst_list_prim_u_8_strict *path;
  struct wire_cst_list_prim_u_8_strict *file_prefix;
  struct wire_cst_list_prim_u_8_strict *file_suffix;
  uint64_t *max_files;
  int32_t rotation;
} wire_cst_tracing_file_configuration;

typedef struct wire_cst_tracing_configuration {
  int32_t log_level;
  struct wire_cst_list_trace_log_packs *trace_log_packs;
  struct wire_cst_list_String *extra_targets;
  bool write_to_stdout_or_system;
  struct wire_cst_tracing_file_configuration *write_to_files;
} wire_cst_tracing_configuration;

typedef struct wire_cst_message_reaction_entry {
  struct wire_cst_list_prim_u_8_strict *key;
  uint32_t count;
  bool contains_own;
  struct wire_cst_list_String *senders;
} wire_cst_message_reaction_entry;

typedef struct wire_cst_list_message_reaction_entry {
  struct wire_cst_message_reaction_entry *ptr;
  int32_t len;
} wire_cst_list_message_reaction_entry;

typedef struct wire_cst_message {
  struct wire_cst_list_prim_u_8_strict *event_id;
  struct wire_cst_list_prim_u_8_strict *transaction_id;
  struct wire_cst_list_prim_u_8_strict *sender;
  struct wire_cst_list_prim_u_8_strict *sender_user_id;
  struct wire_cst_list_prim_u_8_strict *sender_avatar_mxc;
  struct wire_cst_list_prim_u_8_strict *content;
  uint64_t timestamp;
  int32_t message_type;
  int32_t room_msg_kind;
  int32_t send_state;
  struct wire_cst_list_prim_u_8_strict *send_error;
  bool send_recoverable;
  bool is_own;
  struct wire_cst_list_prim_u_8_strict *media_mimetype;
  uint64_t media_size_bytes;
  struct wire_cst_list_prim_u_8_strict *media_blurhash;
  uint32_t media_preview_width;
  uint32_t media_preview_height;
  uint64_t audio_duration_ms;
  struct wire_cst_list_prim_f_32_strict *audio_waveform;
  struct wire_cst_list_prim_u_8_strict *in_reply_to_event_id;
  struct wire_cst_list_prim_u_8_strict *in_reply_to_sender;
  struct wire_cst_list_prim_u_8_strict *in_reply_to_preview;
  int32_t in_reply_to_room_msg_kind;
  struct wire_cst_list_prim_u_8_strict *in_reply_to_media_mimetype;
  uint64_t in_reply_to_media_size_bytes;
  struct wire_cst_list_prim_u_8_strict *in_reply_to_media_blurhash;
  uint32_t in_reply_to_media_preview_width;
  uint32_t in_reply_to_media_preview_height;
  bool in_reply_to_parent_redacted;
  struct wire_cst_list_message_reaction_entry *reactions;
  struct wire_cst_list_prim_u_8_strict *poll_options_json;
  struct wire_cst_list_prim_u_8_strict *poll_state_json;
  struct wire_cst_list_prim_u_8_strict *link_previews_json;
  bool is_redacted;
  uint32_t read_receipt_count;
} wire_cst_message;

typedef struct wire_cst_room_update {
  struct wire_cst_list_prim_u_8_strict *room_id;
  struct wire_cst_list_prim_u_8_strict *raw_name;
  struct wire_cst_list_prim_u_8_strict *display_name;
  bool *is_dm;
  int32_t update_type;
  uint64_t *unread_notifications;
  uint64_t *unread_highlight;
  uint64_t *unread_mentions;
  uint64_t *unread_messages;
  struct wire_cst_message *message;
} wire_cst_room_update;

typedef struct wire_cst_list_message {
  struct wire_cst_message *ptr;
  int32_t len;
} wire_cst_list_message;

typedef struct wire_cst_room_file_item {
  struct wire_cst_list_prim_u_8_strict *event_id;
  struct wire_cst_list_prim_u_8_strict *transaction_id;
  struct wire_cst_list_prim_u_8_strict *sender;
  struct wire_cst_list_prim_u_8_strict *caption;
  uint64_t timestamp;
  int32_t kind;
  bool is_outgoing;
  uint64_t size_bytes;
} wire_cst_room_file_item;

typedef struct wire_cst_list_room_file_item {
  struct wire_cst_room_file_item *ptr;
  int32_t len;
} wire_cst_list_room_file_item;

typedef struct wire_cst_room_link_item {
  struct wire_cst_list_prim_u_8_strict *event_id;
  struct wire_cst_list_prim_u_8_strict *transaction_id;
  struct wire_cst_list_prim_u_8_strict *sender;
  struct wire_cst_list_prim_u_8_strict *body;
  uint64_t timestamp;
  bool is_outgoing;
  struct wire_cst_list_prim_u_8_strict *link_previews_json;
  bool is_link_message;
} wire_cst_room_link_item;

typedef struct wire_cst_list_room_link_item {
  struct wire_cst_room_link_item *ptr;
  int32_t len;
} wire_cst_list_room_link_item;

typedef struct wire_cst_room_member_row {
  struct wire_cst_list_prim_u_8_strict *user_id;
  struct wire_cst_list_prim_u_8_strict *user_id_display;
  struct wire_cst_list_prim_u_8_strict *display_name;
  struct wire_cst_list_prim_u_8_strict *avatar_url;
  int64_t power_level;
  int32_t role;
  bool is_self;
  bool current_user_can_kick;
} wire_cst_room_member_row;

typedef struct wire_cst_list_room_member_row {
  struct wire_cst_room_member_row *ptr;
  int32_t len;
} wire_cst_list_room_member_row;

typedef struct wire_cst_room_poll_item {
  struct wire_cst_list_prim_u_8_strict *event_id;
  struct wire_cst_list_prim_u_8_strict *transaction_id;
  struct wire_cst_list_prim_u_8_strict *sender;
  struct wire_cst_list_prim_u_8_strict *question;
  uint64_t timestamp;
  bool is_outgoing;
} wire_cst_room_poll_item;

typedef struct wire_cst_list_room_poll_item {
  struct wire_cst_room_poll_item *ptr;
  int32_t len;
} wire_cst_list_room_poll_item;

typedef struct wire_cst_list_room_update {
  struct wire_cst_room_update *ptr;
  int32_t len;
} wire_cst_list_room_update;

typedef struct wire_cst_user {
  struct wire_cst_list_prim_u_8_strict *user_id;
  struct wire_cst_list_prim_u_8_strict *user_id_display;
  struct wire_cst_list_prim_u_8_strict *display_name;
  struct wire_cst_list_prim_u_8_strict *avatar_url;
} wire_cst_user;

typedef struct wire_cst_list_user {
  struct wire_cst_user *ptr;
  int32_t len;
} wire_cst_list_user;

typedef struct wire_cst_ClientError_Generic {
  struct wire_cst_list_prim_u_8_strict *msg;
  struct wire_cst_list_prim_u_8_strict *details;
} wire_cst_ClientError_Generic;

typedef union ClientErrorKind {
  struct wire_cst_ClientError_Generic Generic;
} ClientErrorKind;

typedef struct wire_cst_client_error {
  int32_t tag;
  union ClientErrorKind kind;
} wire_cst_client_error;

typedef struct wire_cst_file_send_progress {
  int32_t phase;
  uint64_t current;
  uint64_t total;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_file_send_progress;

typedef struct wire_cst_message_update {
  int32_t message_update_type;
  struct wire_cst_list_message *messages;
  uintptr_t index;
  uintptr_t length;
} wire_cst_message_update;

typedef struct wire_cst_room_details {
  struct wire_cst_list_prim_u_8_strict *room_id;
  struct wire_cst_list_prim_u_8_strict *display_name;
  struct wire_cst_list_prim_u_8_strict *topic;
  bool is_direct;
  bool is_encrypted;
  uint32_t member_count;
  struct wire_cst_list_room_member_row *members;
  struct wire_cst_list_prim_u_8_strict *current_user_id;
  bool current_user_is_admin;
  bool current_user_is_moderator;
} wire_cst_room_details;

typedef struct wire_cst_sync_notification_summary {
  struct wire_cst_list_prim_u_8_strict *room_id;
  struct wire_cst_list_prim_u_8_strict *room_display_name;
  int32_t kind;
  struct wire_cst_list_prim_u_8_strict *sender_id;
  struct wire_cst_list_prim_u_8_strict *sender_display_name;
  struct wire_cst_list_prim_u_8_strict *body_preview;
  bool is_highlight;
  bool is_noisy;
  struct wire_cst_list_prim_u_8_strict *event_id;
} wire_cst_sync_notification_summary;

typedef struct wire_cst_user_search_result {
  struct wire_cst_list_user *users;
  bool limited;
} wire_cst_user_search_result;

void frbgen_matrix_sdk_wire__crate__logger__platform__FieldsFormatterForFiles_default(int64_t port_);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_cancel_timeline_file_send(int64_t port_,
                                                                                               uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_configure(int64_t port_,
                                                                               struct wire_cst_client_config *config);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_direct_room(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *user_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_group_room(int64_t port_,
                                                                                       uintptr_t that,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       struct wire_cst_list_String *user_ids);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_fetch_room_message_media(int64_t port_,
                                                                                              uintptr_t that,
                                                                                              struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                              struct wire_cst_list_prim_u_8_strict *event_id,
                                                                                              bool thumbnail);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_fetch_user_avatar_thumbnail(int64_t port_,
                                                                                                 uintptr_t that,
                                                                                                 struct wire_cst_list_prim_u_8_strict *mxc_uri);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_all_rooms(int64_t port_,
                                                                                   uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_display_name(int64_t port_,
                                                                                      uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_existing_dm_room_id(int64_t port_,
                                                                                             uintptr_t that,
                                                                                             struct wire_cst_list_prim_u_8_strict *user_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_older_messages(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                        uint16_t count);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_profile_avatar_mxc(int64_t port_,
                                                                                            uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_profile_initials(int64_t port_,
                                                                                          uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_room_details(int64_t port_,
                                                                                      uintptr_t that,
                                                                                      struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_timeline_items_by_room_id(int64_t port_,
                                                                                                   uintptr_t that,
                                                                                                   struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_is_client_authenticated(int64_t port_,
                                                                                             uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_join_room(int64_t port_,
                                                                               uintptr_t that,
                                                                               struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_kick_room_member(int64_t port_,
                                                                                      uintptr_t that,
                                                                                      struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                      struct wire_cst_list_prim_u_8_strict *user_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_and_forget_room(int64_t port_,
                                                                                           uintptr_t that,
                                                                                           struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_room(int64_t port_,
                                                                                uintptr_t that,
                                                                                struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_files(int64_t port_,
                                                                                     uintptr_t that,
                                                                                     struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                     int32_t filter);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_links(int64_t port_,
                                                                                     uintptr_t that,
                                                                                     struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                     int32_t filter);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_polls(int64_t port_,
                                                                                     uintptr_t that,
                                                                                     struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                     int32_t filter);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_login(int64_t port_,
                                                                           uintptr_t that,
                                                                           struct wire_cst_list_prim_u_8_strict *username,
                                                                           struct wire_cst_list_prim_u_8_strict *password);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_logout(int64_t port_,
                                                                            uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_mark_timeline_as_read(int64_t port_,
                                                                                           uintptr_t that,
                                                                                           struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_pause_sync_service(int64_t port_,
                                                                                        uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_redact_timeline_event(int64_t port_,
                                                                                           uintptr_t that,
                                                                                           struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                           struct wire_cst_list_prim_u_8_strict *event_id,
                                                                                           struct wire_cst_list_prim_u_8_strict *transaction_id,
                                                                                           struct wire_cst_list_prim_u_8_strict *reason);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register(int64_t port_,
                                                                              uintptr_t that,
                                                                              struct wire_cst_list_prim_u_8_strict *username,
                                                                              struct wire_cst_list_prim_u_8_strict *password,
                                                                              struct wire_cst_list_prim_u_8_strict *display_name,
                                                                              struct wire_cst_list_prim_u_8_strict *token);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register_pusher(int64_t port_,
                                                                                     uintptr_t that,
                                                                                     struct wire_cst_list_prim_u_8_strict *push_key,
                                                                                     struct wire_cst_list_prim_u_8_strict *app_id,
                                                                                     struct wire_cst_list_prim_u_8_strict *url,
                                                                                     struct wire_cst_list_prim_u_8_strict *display_name,
                                                                                     struct wire_cst_list_prim_u_8_strict *profile_tag,
                                                                                     struct wire_cst_list_prim_u_8_strict *lang,
                                                                                     struct wire_cst_list_prim_u_8_strict *app_display_name);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_remove_profile_avatar(int64_t port_,
                                                                                           uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_restart_sync_service(int64_t port_,
                                                                                          uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_retry_failed_send(int64_t port_,
                                                                                       uintptr_t that,
                                                                                       struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                       struct wire_cst_list_prim_u_8_strict *transaction_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_room_list_subscribe_to_rooms(int64_t port_,
                                                                                                  uintptr_t that,
                                                                                                  struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_search_users(int64_t port_,
                                                                                  uintptr_t that,
                                                                                  struct wire_cst_list_prim_u_8_strict *query);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_message(int64_t port_,
                                                                                  uintptr_t that,
                                                                                  struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                  struct wire_cst_list_prim_u_8_strict *content);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_poll(int64_t port_,
                                                                               uintptr_t that,
                                                                               struct wire_cst_list_prim_u_8_strict *room_id,
                                                                               struct wire_cst_list_prim_u_8_strict *question,
                                                                               struct wire_cst_list_String *answer_texts,
                                                                               bool kind_disclosed,
                                                                               uint64_t max_selections);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_poll_response(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                        struct wire_cst_list_prim_u_8_strict *poll_start_event_id,
                                                                                        struct wire_cst_list_String *answer_ids);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_reply(int64_t port_,
                                                                                uintptr_t that,
                                                                                struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                struct wire_cst_list_prim_u_8_strict *content,
                                                                                struct wire_cst_list_prim_u_8_strict *reply_to_event_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_timeline_file(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                        struct wire_cst_list_prim_u_8_strict *file_path,
                                                                                        struct wire_cst_list_prim_u_8_strict *caption,
                                                                                        struct wire_cst_list_prim_u_8_strict *app_thumbnail_jpeg_path,
                                                                                        uint64_t *audio_duration_ms,
                                                                                        struct wire_cst_list_prim_f_32_strict *audio_waveform_normalized,
                                                                                        bool audio_as_voice_message);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_timeline_file_with_progress(int64_t port_,
                                                                                                      uintptr_t that,
                                                                                                      struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                                      struct wire_cst_list_prim_u_8_strict *file_path,
                                                                                                      struct wire_cst_list_prim_u_8_strict *caption,
                                                                                                      struct wire_cst_list_prim_u_8_strict *app_thumbnail_jpeg_path,
                                                                                                      uint64_t *audio_duration_ms,
                                                                                                      struct wire_cst_list_prim_f_32_strict *audio_waveform_normalized,
                                                                                                      bool audio_as_voice_message,
                                                                                                      struct wire_cst_list_prim_u_8_strict *progress);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_display_name(int64_t port_,
                                                                                      uintptr_t that,
                                                                                      struct wire_cst_list_prim_u_8_strict *display_name);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_profile_initials(int64_t port_,
                                                                                          uintptr_t that,
                                                                                          struct wire_cst_list_prim_u_8_strict *initials);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_room_member_power_level(int64_t port_,
                                                                                                 uintptr_t that,
                                                                                                 struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                                 struct wire_cst_list_prim_u_8_strict *user_id,
                                                                                                 int64_t power_level);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_start_sync_service(int64_t port_,
                                                                                        uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_sync_state(int64_t port_,
                                                                                          uintptr_t that,
                                                                                          struct wire_cst_list_prim_u_8_strict *stream);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_all_room_updates(int64_t port_,
                                                                                                   uintptr_t that,
                                                                                                   struct wire_cst_list_prim_u_8_strict *stream);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_room_list(int64_t port_,
                                                                                            uintptr_t that,
                                                                                            struct wire_cst_list_prim_u_8_strict *stream);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_sync_notifications(int64_t port_,
                                                                                                     uintptr_t that,
                                                                                                     struct wire_cst_list_prim_u_8_strict *stream);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_list(int64_t port_,
                                                                                                uintptr_t that,
                                                                                                struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                                struct wire_cst_list_prim_u_8_strict *stream);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_updates(int64_t port_,
                                                                                                   uintptr_t that,
                                                                                                   struct wire_cst_list_prim_u_8_strict *stream,
                                                                                                   struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_take_last_sent_room_update(int64_t port_,
                                                                                                uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_toggle_timeline_reaction(int64_t port_,
                                                                                              uintptr_t that,
                                                                                              struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                              struct wire_cst_list_prim_u_8_strict *event_id,
                                                                                              struct wire_cst_list_prim_u_8_strict *transaction_id,
                                                                                              struct wire_cst_list_prim_u_8_strict *reaction_key);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_unregister_pusher(int64_t port_,
                                                                                       uintptr_t that,
                                                                                       struct wire_cst_list_prim_u_8_strict *push_key,
                                                                                       struct wire_cst_list_prim_u_8_strict *app_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_upload_profile_avatar(int64_t port_,
                                                                                           uintptr_t that,
                                                                                           struct wire_cst_list_prim_u_8_strict *mime_type,
                                                                                           struct wire_cst_list_prim_u_8_loose *data);

void frbgen_matrix_sdk_wire__crate__api__document_preview__document_preview_json(int64_t port_,
                                                                                 struct wire_cst_list_prim_u_8_strict *extension,
                                                                                 struct wire_cst_list_prim_u_8_loose *data);

void frbgen_matrix_sdk_wire__crate__logger__platform__init_platform(int64_t port_,
                                                                    struct wire_cst_tracing_configuration *config,
                                                                    bool use_lightweight_tokio_runtime);

void frbgen_matrix_sdk_wire__crate__logger__tracing__log_event(int64_t port_,
                                                               struct wire_cst_list_prim_u_8_strict *file,
                                                               uint32_t *line,
                                                               int32_t level,
                                                               struct wire_cst_list_prim_u_8_strict *target,
                                                               struct wire_cst_list_prim_u_8_strict *message);

void frbgen_matrix_sdk_wire__crate__logger__platform__reload_tracing_file_writer(int64_t port_,
                                                                                 struct wire_cst_tracing_file_configuration *configuration);

void frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_http_tracing_logs(int64_t port_,
                                                                                  struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_tracing_logs(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient(const void *ptr);

bool *frbgen_matrix_sdk_cst_new_box_autoadd_bool(bool value);

struct wire_cst_client_config *frbgen_matrix_sdk_cst_new_box_autoadd_client_config(void);

struct wire_cst_message *frbgen_matrix_sdk_cst_new_box_autoadd_message(void);

struct wire_cst_room_update *frbgen_matrix_sdk_cst_new_box_autoadd_room_update(void);

struct wire_cst_tracing_configuration *frbgen_matrix_sdk_cst_new_box_autoadd_tracing_configuration(void);

struct wire_cst_tracing_file_configuration *frbgen_matrix_sdk_cst_new_box_autoadd_tracing_file_configuration(void);

uint32_t *frbgen_matrix_sdk_cst_new_box_autoadd_u_32(uint32_t value);

uint64_t *frbgen_matrix_sdk_cst_new_box_autoadd_u_64(uint64_t value);

struct wire_cst_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate *frbgen_matrix_sdk_cst_new_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(int32_t len);

struct wire_cst_list_String *frbgen_matrix_sdk_cst_new_list_String(int32_t len);

struct wire_cst_list_message *frbgen_matrix_sdk_cst_new_list_message(int32_t len);

struct wire_cst_list_message_reaction_entry *frbgen_matrix_sdk_cst_new_list_message_reaction_entry(int32_t len);

struct wire_cst_list_prim_f_32_strict *frbgen_matrix_sdk_cst_new_list_prim_f_32_strict(int32_t len);

struct wire_cst_list_prim_u_8_loose *frbgen_matrix_sdk_cst_new_list_prim_u_8_loose(int32_t len);

struct wire_cst_list_prim_u_8_strict *frbgen_matrix_sdk_cst_new_list_prim_u_8_strict(int32_t len);

struct wire_cst_list_room_file_item *frbgen_matrix_sdk_cst_new_list_room_file_item(int32_t len);

struct wire_cst_list_room_link_item *frbgen_matrix_sdk_cst_new_list_room_link_item(int32_t len);

struct wire_cst_list_room_member_row *frbgen_matrix_sdk_cst_new_list_room_member_row(int32_t len);

struct wire_cst_list_room_poll_item *frbgen_matrix_sdk_cst_new_list_room_poll_item(int32_t len);

struct wire_cst_list_room_update *frbgen_matrix_sdk_cst_new_list_room_update(int32_t len);

struct wire_cst_list_trace_log_packs *frbgen_matrix_sdk_cst_new_list_trace_log_packs(int32_t len);

struct wire_cst_list_user *frbgen_matrix_sdk_cst_new_list_user(int32_t len);

/**
 * JNI entrypoint: called from Kotlin `RustlsInit.init(context)`.
 * Initializes the platform certificate verifier so HTTPS works on Android.
 *
 * Signature matches JNI native method `init(Landroid/content/Context;)V` on
 * class `dev.inve.matrixchat.RustlsInit`.
 */
void Java_dev_inve_matrixchat_RustlsInit_init(void *raw_env, void *_class, void *raw_context);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_bool);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_client_config);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tracing_configuration);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tracing_file_configuration);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_u_64);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_String);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_message_reaction_entry);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_prim_f_32_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_prim_u_8_loose);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_file_item);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_link_item);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_member_row);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_poll_item);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_trace_log_packs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_user);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__document_preview__document_preview_json);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_cancel_timeline_file_send);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_configure);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_direct_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_group_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_fetch_room_message_media);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_fetch_user_avatar_thumbnail);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_all_rooms);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_display_name);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_existing_dm_room_id);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_older_messages);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_profile_avatar_mxc);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_profile_initials);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_room_details);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_timeline_items_by_room_id);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_is_client_authenticated);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_join_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_kick_room_member);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_and_forget_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_files);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_links);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_list_room_polls);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_login);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_logout);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_mark_timeline_as_read);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_pause_sync_service);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_redact_timeline_event);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register_pusher);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_remove_profile_avatar);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_restart_sync_service);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_retry_failed_send);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_room_list_subscribe_to_rooms);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_search_users);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_poll);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_poll_response);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_reply);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_timeline_file);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_timeline_file_with_progress);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_display_name);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_profile_initials);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_room_member_power_level);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_start_sync_service);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_sync_state);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_all_room_updates);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_room_list);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_sync_notifications);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_list);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_updates);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_take_last_sent_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_toggle_timeline_reaction);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_unregister_pusher);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_upload_profile_avatar);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__FieldsFormatterForFiles_default);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__init_platform);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__reload_tracing_file_writer);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_http_tracing_logs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_tracing_logs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__tracing__log_event);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
