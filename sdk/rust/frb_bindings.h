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



typedef struct wire_cst_list_prim_u_8_loose {
  uint8_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_8_loose;

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
  uintptr_t *rhttp_client;
} wire_cst_client_config;

typedef struct wire_cst_list_String {
  struct wire_cst_list_prim_u_8_strict **ptr;
  int32_t len;
} wire_cst_list_String;

typedef struct wire_cst_record_string_list_string {
  struct wire_cst_list_prim_u_8_strict *field0;
  struct wire_cst_list_String *field1;
} wire_cst_record_string_list_string;

typedef struct wire_cst_list_record_string_list_string {
  struct wire_cst_record_string_list_string *ptr;
  int32_t len;
} wire_cst_list_record_string_list_string;

typedef struct wire_cst_static_dns_settings {
  struct wire_cst_list_record_string_list_string *overrides;
  struct wire_cst_list_prim_u_8_strict *fallback;
} wire_cst_static_dns_settings;

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

typedef struct wire_cst_cookie_settings {
  bool store_cookies;
} wire_cst_cookie_settings;

typedef struct wire_cst_timeout_settings {
  int64_t *timeout_ms;
  int64_t *connect_timeout_ms;
  int64_t *keep_alive_timeout_ms;
  int64_t *keep_alive_ping_ms;
} wire_cst_timeout_settings;

typedef struct wire_cst_custom_proxy {
  struct wire_cst_list_prim_u_8_strict *url;
  int32_t condition;
} wire_cst_custom_proxy;

typedef struct wire_cst_list_custom_proxy {
  struct wire_cst_custom_proxy *ptr;
  int32_t len;
} wire_cst_list_custom_proxy;

typedef struct wire_cst_ProxySettings_CustomProxyList {
  struct wire_cst_list_custom_proxy *field0;
} wire_cst_ProxySettings_CustomProxyList;

typedef union ProxySettingsKind {
  struct wire_cst_ProxySettings_CustomProxyList CustomProxyList;
} ProxySettingsKind;

typedef struct wire_cst_proxy_settings {
  int32_t tag;
  union ProxySettingsKind kind;
} wire_cst_proxy_settings;

typedef struct wire_cst_RedirectSettings_LimitedRedirects {
  int32_t field0;
} wire_cst_RedirectSettings_LimitedRedirects;

typedef union RedirectSettingsKind {
  struct wire_cst_RedirectSettings_LimitedRedirects LimitedRedirects;
} RedirectSettingsKind;

typedef struct wire_cst_redirect_settings {
  int32_t tag;
  union RedirectSettingsKind kind;
} wire_cst_redirect_settings;

typedef struct wire_cst_list_list_prim_u_8_strict {
  struct wire_cst_list_prim_u_8_strict **ptr;
  int32_t len;
} wire_cst_list_list_prim_u_8_strict;

typedef struct wire_cst_client_certificate {
  struct wire_cst_list_prim_u_8_strict *certificate;
  struct wire_cst_list_prim_u_8_strict *private_key;
} wire_cst_client_certificate;

typedef struct wire_cst_tls_settings {
  bool trust_root_certificates;
  struct wire_cst_list_list_prim_u_8_strict *trusted_root_certificates;
  bool verify_certificates;
  struct wire_cst_client_certificate *client_certificate;
  int32_t *min_tls_version;
  int32_t *max_tls_version;
  bool sni;
} wire_cst_tls_settings;

typedef struct wire_cst_client_settings {
  struct wire_cst_cookie_settings *cookie_settings;
  int32_t http_version_pref;
  struct wire_cst_timeout_settings *timeout_settings;
  bool throw_on_status_code;
  struct wire_cst_proxy_settings *proxy_settings;
  struct wire_cst_redirect_settings *redirect_settings;
  struct wire_cst_tls_settings *tls_settings;
  uintptr_t *dns_settings;
  struct wire_cst_list_prim_u_8_strict *user_agent;
} wire_cst_client_settings;

typedef struct wire_cst_http_method {
  struct wire_cst_list_prim_u_8_strict *method;
} wire_cst_http_method;

typedef struct wire_cst_record_string_string {
  struct wire_cst_list_prim_u_8_strict *field0;
  struct wire_cst_list_prim_u_8_strict *field1;
} wire_cst_record_string_string;

typedef struct wire_cst_list_record_string_string {
  struct wire_cst_record_string_string *ptr;
  int32_t len;
} wire_cst_list_record_string_string;

typedef struct wire_cst_HttpHeaders_Map {
  struct wire_cst_list_record_string_string *field0;
} wire_cst_HttpHeaders_Map;

typedef struct wire_cst_HttpHeaders_List {
  struct wire_cst_list_record_string_string *field0;
} wire_cst_HttpHeaders_List;

typedef union HttpHeadersKind {
  struct wire_cst_HttpHeaders_Map Map;
  struct wire_cst_HttpHeaders_List List;
} HttpHeadersKind;

typedef struct wire_cst_http_headers {
  int32_t tag;
  union HttpHeadersKind kind;
} wire_cst_http_headers;

typedef struct wire_cst_HttpBody_Text {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_HttpBody_Text;

typedef struct wire_cst_HttpBody_Bytes {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_HttpBody_Bytes;

typedef struct wire_cst_HttpBody_Form {
  struct wire_cst_list_record_string_string *field0;
} wire_cst_HttpBody_Form;

typedef struct wire_cst_MultipartValue_Text {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_MultipartValue_Text;

typedef struct wire_cst_MultipartValue_Bytes {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_MultipartValue_Bytes;

typedef struct wire_cst_MultipartValue_File {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_MultipartValue_File;

typedef union MultipartValueKind {
  struct wire_cst_MultipartValue_Text Text;
  struct wire_cst_MultipartValue_Bytes Bytes;
  struct wire_cst_MultipartValue_File File;
} MultipartValueKind;

typedef struct wire_cst_multipart_value {
  int32_t tag;
  union MultipartValueKind kind;
} wire_cst_multipart_value;

typedef struct wire_cst_multipart_item {
  struct wire_cst_multipart_value value;
  struct wire_cst_list_prim_u_8_strict *file_name;
  struct wire_cst_list_prim_u_8_strict *content_type;
} wire_cst_multipart_item;

typedef struct wire_cst_record_string_multipart_item {
  struct wire_cst_list_prim_u_8_strict *field0;
  struct wire_cst_multipart_item field1;
} wire_cst_record_string_multipart_item;

typedef struct wire_cst_list_record_string_multipart_item {
  struct wire_cst_record_string_multipart_item *ptr;
  int32_t len;
} wire_cst_list_record_string_multipart_item;

typedef struct wire_cst_multipart_payload {
  struct wire_cst_list_record_string_multipart_item *parts;
} wire_cst_multipart_payload;

typedef struct wire_cst_HttpBody_Multipart {
  struct wire_cst_multipart_payload *field0;
} wire_cst_HttpBody_Multipart;

typedef union HttpBodyKind {
  struct wire_cst_HttpBody_Text Text;
  struct wire_cst_HttpBody_Bytes Bytes;
  struct wire_cst_HttpBody_Form Form;
  struct wire_cst_HttpBody_Multipart Multipart;
} HttpBodyKind;

typedef struct wire_cst_http_body {
  int32_t tag;
  union HttpBodyKind kind;
} wire_cst_http_body;

typedef struct wire_cst_HttpResponseBody_Text {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_HttpResponseBody_Text;

typedef struct wire_cst_HttpResponseBody_Bytes {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_HttpResponseBody_Bytes;

typedef union HttpResponseBodyKind {
  struct wire_cst_HttpResponseBody_Text Text;
  struct wire_cst_HttpResponseBody_Bytes Bytes;
} HttpResponseBodyKind;

typedef struct wire_cst_http_response_body {
  int32_t tag;
  union HttpResponseBodyKind kind;
} wire_cst_http_response_body;

typedef struct wire_cst_message {
  struct wire_cst_list_prim_u_8_strict *event_id;
  struct wire_cst_list_prim_u_8_strict *sender;
  struct wire_cst_list_prim_u_8_strict *content;
  uint64_t timestamp;
  int32_t message_type;
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

typedef struct wire_cst_list_room_update {
  struct wire_cst_room_update *ptr;
  int32_t len;
} wire_cst_list_room_update;

typedef struct wire_cst_user {
  struct wire_cst_list_prim_u_8_strict *user_id;
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

typedef struct wire_cst_http_response {
  struct wire_cst_list_prim_u_8_strict *remote_ip;
  struct wire_cst_list_record_string_string *headers;
  int32_t version;
  uint16_t status_code;
  struct wire_cst_http_response_body body;
} wire_cst_http_response;

typedef struct wire_cst_message_update {
  int32_t message_update_type;
  struct wire_cst_list_message *messages;
  uintptr_t index;
  uintptr_t length;
} wire_cst_message_update;

typedef struct wire_cst_record_auto_owned_rust_opaque_flutter_rust_bridgefor_generated_rust_auto_opaque_inner_dart_2_rust_stream_sink_auto_owned_rust_opaque_flutter_rust_bridgefor_generated_rust_auto_opaque_inner_dart_2_rust_stream_receiver {
  uintptr_t field0;
  uintptr_t field1;
} wire_cst_record_auto_owned_rust_opaque_flutter_rust_bridgefor_generated_rust_auto_opaque_inner_dart_2_rust_stream_sink_auto_owned_rust_opaque_flutter_rust_bridgefor_generated_rust_auto_opaque_inner_dart_2_rust_stream_receiver;

typedef struct wire_cst_RhttpError_RhttpStatusCodeError {
  uint16_t field0;
  struct wire_cst_list_record_string_string *field1;
  struct wire_cst_http_response_body *field2;
} wire_cst_RhttpError_RhttpStatusCodeError;

typedef struct wire_cst_RhttpError_RhttpInvalidCertificateError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_RhttpError_RhttpInvalidCertificateError;

typedef struct wire_cst_RhttpError_RhttpConnectionError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_RhttpError_RhttpConnectionError;

typedef struct wire_cst_RhttpError_RhttpUnknownError {
  struct wire_cst_list_prim_u_8_strict *field0;
} wire_cst_RhttpError_RhttpUnknownError;

typedef union RhttpErrorKind {
  struct wire_cst_RhttpError_RhttpStatusCodeError RhttpStatusCodeError;
  struct wire_cst_RhttpError_RhttpInvalidCertificateError RhttpInvalidCertificateError;
  struct wire_cst_RhttpError_RhttpConnectionError RhttpConnectionError;
  struct wire_cst_RhttpError_RhttpUnknownError RhttpUnknownError;
} RhttpErrorKind;

typedef struct wire_cst_rhttp_error {
  int32_t tag;
  union RhttpErrorKind kind;
} wire_cst_rhttp_error;

typedef struct wire_cst_user_search_result {
  struct wire_cst_list_user *users;
  bool limited;
} wire_cst_user_search_result;

void frbgen_matrix_sdk_wire__crate__rhttp__api__stream__Dart2RustStreamSink_add(int64_t port_,
                                                                                uintptr_t that,
                                                                                struct wire_cst_list_prim_u_8_loose *data);

void frbgen_matrix_sdk_wire__crate__rhttp__api__stream__Dart2RustStreamSink_close(int64_t port_,
                                                                                  uintptr_t that);

void frbgen_matrix_sdk_wire__crate__logger__platform__FieldsFormatterForFiles_default(int64_t port_);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_configure(int64_t port_,
                                                                               struct wire_cst_client_config *config);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_direct_room(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *user_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_group_room(int64_t port_,
                                                                                       uintptr_t that,
                                                                                       struct wire_cst_list_prim_u_8_strict *name,
                                                                                       struct wire_cst_list_String *user_ids);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_all_rooms(int64_t port_,
                                                                                   uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_display_name(int64_t port_,
                                                                                      uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_older_messages(int64_t port_,
                                                                                        uintptr_t that,
                                                                                        struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                        uint16_t count);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_timeline_items_by_room_id(int64_t port_,
                                                                                                   uintptr_t that,
                                                                                                   struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_is_client_authenticated(int64_t port_,
                                                                                             uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_join_room(int64_t port_,
                                                                               uintptr_t that,
                                                                               struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_room(int64_t port_,
                                                                                uintptr_t that,
                                                                                struct wire_cst_list_prim_u_8_strict *room_id);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_login(int64_t port_,
                                                                           uintptr_t that,
                                                                           struct wire_cst_list_prim_u_8_strict *username,
                                                                           struct wire_cst_list_prim_u_8_strict *password);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_logout(int64_t port_,
                                                                            uintptr_t that);

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

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_restart_sync_service(int64_t port_,
                                                                                          uintptr_t that);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_search_users(int64_t port_,
                                                                                  uintptr_t that,
                                                                                  struct wire_cst_list_prim_u_8_strict *query);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_message(int64_t port_,
                                                                                  uintptr_t that,
                                                                                  struct wire_cst_list_prim_u_8_strict *room_id,
                                                                                  struct wire_cst_list_prim_u_8_strict *content);

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_display_name(int64_t port_,
                                                                                      uintptr_t that,
                                                                                      struct wire_cst_list_prim_u_8_strict *display_name);

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

void frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_unregister_pusher(int64_t port_,
                                                                                       uintptr_t that,
                                                                                       struct wire_cst_list_prim_u_8_strict *push_key,
                                                                                       struct wire_cst_list_prim_u_8_strict *app_id);

void frbgen_matrix_sdk_wire__crate__rhttp__api__http__cancel_request(int64_t port_,
                                                                     uintptr_t token);

void frbgen_matrix_sdk_wire__crate__rhttp__api__http__cancel_running_requests(int64_t port_,
                                                                              uintptr_t client);

void frbgen_matrix_sdk_wire__crate__rhttp__api__client__client_settings_default(int64_t port_);

WireSyncRust2DartDco frbgen_matrix_sdk_wire__crate__rhttp__api__client__create_dynamic_resolver_sync(const void *resolver);

WireSyncRust2DartDco frbgen_matrix_sdk_wire__crate__rhttp__api__client__create_static_resolver_sync(struct wire_cst_static_dns_settings *settings);

void frbgen_matrix_sdk_wire__crate__rhttp__api__stream__create_stream(int64_t port_);

WireSyncRust2DartDco frbgen_matrix_sdk_wire__crate__rhttp__api__client__get_default_client_sync(void);

void frbgen_matrix_sdk_wire__crate__logger__platform__init_platform(int64_t port_,
                                                                    struct wire_cst_tracing_configuration *config,
                                                                    bool use_lightweight_tokio_runtime);

void frbgen_matrix_sdk_wire__crate__logger__tracing__log_event(int64_t port_,
                                                               struct wire_cst_list_prim_u_8_strict *file,
                                                               uint32_t *line,
                                                               int32_t level,
                                                               struct wire_cst_list_prim_u_8_strict *target,
                                                               struct wire_cst_list_prim_u_8_strict *message);

void frbgen_matrix_sdk_wire__crate__rhttp__api__http__make_http_request(int64_t port_,
                                                                        uintptr_t client,
                                                                        struct wire_cst_client_settings *settings,
                                                                        struct wire_cst_http_method *method,
                                                                        struct wire_cst_list_prim_u_8_strict *url,
                                                                        struct wire_cst_list_record_string_string *query,
                                                                        struct wire_cst_http_headers *headers,
                                                                        struct wire_cst_http_body *body,
                                                                        uintptr_t *body_stream,
                                                                        int32_t expect_body,
                                                                        const void *on_cancel_token,
                                                                        bool cancelable);

void frbgen_matrix_sdk_wire__crate__rhttp__api__http__make_http_request_receive_stream(int64_t port_,
                                                                                       uintptr_t client,
                                                                                       struct wire_cst_client_settings *settings,
                                                                                       struct wire_cst_http_method *method,
                                                                                       struct wire_cst_list_prim_u_8_strict *url,
                                                                                       struct wire_cst_list_record_string_string *query,
                                                                                       struct wire_cst_http_headers *headers,
                                                                                       struct wire_cst_http_body *body,
                                                                                       uintptr_t *body_stream,
                                                                                       struct wire_cst_list_prim_u_8_strict *stream_sink,
                                                                                       const void *on_response,
                                                                                       const void *on_error,
                                                                                       const void *on_cancel_token,
                                                                                       bool cancelable);

void frbgen_matrix_sdk_wire__crate__rhttp__api__http__register_client(int64_t port_,
                                                                      struct wire_cst_client_settings *settings);

WireSyncRust2DartDco frbgen_matrix_sdk_wire__crate__rhttp__api__http__register_client_sync(struct wire_cst_client_settings *settings);

void frbgen_matrix_sdk_wire__crate__logger__platform__reload_tracing_file_writer(int64_t port_,
                                                                                 struct wire_cst_tracing_file_configuration *configuration);

void frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_http_tracing_logs(int64_t port_,
                                                                                  struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_tracing_logs(int64_t port_,
                                                                             struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCancellationToken(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCancellationToken(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamSink(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamSink(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient(const void *ptr);

void frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient(const void *ptr);

void frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient(const void *ptr);

uintptr_t *frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver(uintptr_t value);

uintptr_t *frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings(uintptr_t value);

uintptr_t *frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient(uintptr_t value);

bool *frbgen_matrix_sdk_cst_new_box_autoadd_bool(bool value);

struct wire_cst_client_certificate *frbgen_matrix_sdk_cst_new_box_autoadd_client_certificate(void);

struct wire_cst_client_config *frbgen_matrix_sdk_cst_new_box_autoadd_client_config(void);

struct wire_cst_client_settings *frbgen_matrix_sdk_cst_new_box_autoadd_client_settings(void);

struct wire_cst_cookie_settings *frbgen_matrix_sdk_cst_new_box_autoadd_cookie_settings(void);

struct wire_cst_http_body *frbgen_matrix_sdk_cst_new_box_autoadd_http_body(void);

struct wire_cst_http_headers *frbgen_matrix_sdk_cst_new_box_autoadd_http_headers(void);

struct wire_cst_http_method *frbgen_matrix_sdk_cst_new_box_autoadd_http_method(void);

struct wire_cst_http_response_body *frbgen_matrix_sdk_cst_new_box_autoadd_http_response_body(void);

int64_t *frbgen_matrix_sdk_cst_new_box_autoadd_i_64(int64_t value);

struct wire_cst_message *frbgen_matrix_sdk_cst_new_box_autoadd_message(void);

struct wire_cst_multipart_payload *frbgen_matrix_sdk_cst_new_box_autoadd_multipart_payload(void);

struct wire_cst_proxy_settings *frbgen_matrix_sdk_cst_new_box_autoadd_proxy_settings(void);

struct wire_cst_redirect_settings *frbgen_matrix_sdk_cst_new_box_autoadd_redirect_settings(void);

struct wire_cst_room_update *frbgen_matrix_sdk_cst_new_box_autoadd_room_update(void);

struct wire_cst_static_dns_settings *frbgen_matrix_sdk_cst_new_box_autoadd_static_dns_settings(void);

struct wire_cst_timeout_settings *frbgen_matrix_sdk_cst_new_box_autoadd_timeout_settings(void);

struct wire_cst_tls_settings *frbgen_matrix_sdk_cst_new_box_autoadd_tls_settings(void);

int32_t *frbgen_matrix_sdk_cst_new_box_autoadd_tls_version(int32_t value);

struct wire_cst_tracing_configuration *frbgen_matrix_sdk_cst_new_box_autoadd_tracing_configuration(void);

struct wire_cst_tracing_file_configuration *frbgen_matrix_sdk_cst_new_box_autoadd_tracing_file_configuration(void);

uint32_t *frbgen_matrix_sdk_cst_new_box_autoadd_u_32(uint32_t value);

uint64_t *frbgen_matrix_sdk_cst_new_box_autoadd_u_64(uint64_t value);

struct wire_cst_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate *frbgen_matrix_sdk_cst_new_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate(int32_t len);

struct wire_cst_list_String *frbgen_matrix_sdk_cst_new_list_String(int32_t len);

struct wire_cst_list_custom_proxy *frbgen_matrix_sdk_cst_new_list_custom_proxy(int32_t len);

struct wire_cst_list_list_prim_u_8_strict *frbgen_matrix_sdk_cst_new_list_list_prim_u_8_strict(int32_t len);

struct wire_cst_list_message *frbgen_matrix_sdk_cst_new_list_message(int32_t len);

struct wire_cst_list_prim_u_8_loose *frbgen_matrix_sdk_cst_new_list_prim_u_8_loose(int32_t len);

struct wire_cst_list_prim_u_8_strict *frbgen_matrix_sdk_cst_new_list_prim_u_8_strict(int32_t len);

struct wire_cst_list_record_string_list_string *frbgen_matrix_sdk_cst_new_list_record_string_list_string(int32_t len);

struct wire_cst_list_record_string_multipart_item *frbgen_matrix_sdk_cst_new_list_record_string_multipart_item(int32_t len);

struct wire_cst_list_record_string_string *frbgen_matrix_sdk_cst_new_list_record_string_string(int32_t len);

struct wire_cst_list_room_update *frbgen_matrix_sdk_cst_new_list_room_update(int32_t len);

struct wire_cst_list_trace_log_packs *frbgen_matrix_sdk_cst_new_list_trace_log_packs(int32_t len);

struct wire_cst_list_user *frbgen_matrix_sdk_cst_new_list_user(int32_t len);

/**
 * JNI entry point: initializes rustls-platform-verifier with the Android context.
 * Called from Kotlin `RustlsInit.initVerifier(context)` so TLS uses the system trust store.
 *
 * Symbol name must match exactly: Java_<package>_<Class>_<method>
 */
void Java_dev_inve_matrixchat_RustlsInit_initVerifier(JNIEnv *env, jclass _class, jobject context);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_bool);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_client_certificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_client_config);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_client_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_cookie_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_http_body);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_http_headers);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_http_method);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_http_response_body);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_i_64);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_multipart_payload);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_proxy_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_redirect_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_static_dns_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_timeout_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tls_settings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tls_version);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tracing_configuration);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_tracing_file_configuration);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_box_autoadd_u_64);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_Auto_Owned_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_String);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_custom_proxy);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_prim_u_8_loose);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_record_string_list_string);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_record_string_multipart_item);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_record_string_string);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_trace_log_packs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_cst_new_list_user);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCancellationToken);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamSink);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCancellationToken);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerCertificate);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamReceiver);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDart2RustStreamSink);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerDnsSettings);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerFieldsFormatterForFiles);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerMatrixClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRequestClient);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_configure);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_direct_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_create_group_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_all_rooms);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_display_name);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_older_messages);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_get_timeline_items_by_room_id);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_is_client_authenticated);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_join_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_leave_room);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_login);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_logout);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_register_pusher);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_restart_sync_service);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_search_users);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_send_message);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_set_display_name);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_start_sync_service);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_sync_state);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_all_room_updates);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_room_list);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_list);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_subscribe_to_timeline_updates);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_take_last_sent_room_update);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__api__matrix_client__MatrixClient_unregister_pusher);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__FieldsFormatterForFiles_default);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__init_platform);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__reload_tracing_file_writer);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_http_tracing_logs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__platform__subscribe_tracing_logs);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__logger__tracing__log_event);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__client__client_settings_default);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__client__create_dynamic_resolver_sync);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__client__create_static_resolver_sync);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__client__get_default_client_sync);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__cancel_request);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__cancel_running_requests);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__make_http_request);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__make_http_request_receive_stream);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__register_client);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__http__register_client_sync);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__stream__Dart2RustStreamSink_add);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__stream__Dart2RustStreamSink_close);
    dummy_var ^= ((int64_t) (void*) frbgen_matrix_sdk_wire__crate__rhttp__api__stream__create_stream);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
