use crate::frb_generated::StreamSink;
use once_cell::sync::OnceCell;
use tracing::error;

static LOG_STREAM_SINK: OnceCell<StreamSink<LogEntry>> = OnceCell::new();

pub fn init_logger(log_stream: StreamSink<LogEntry>) {
    create_log_stream(log_stream);
}

pub struct LogEntry {
    pub level: String,
    pub message: String,
    pub timestamp: i64,
    pub tag: String,
}

pub fn create_log_stream(s: StreamSink<LogEntry>) {
    match LOG_STREAM_SINK.set(s) {
        Ok(_) => {}
        Err(_) => {
            error!("Failed to set log stream sink");
        }
    }
}

pub fn log_debug(message: String) {
    _log("debug".to_string(), message, "rust".to_string());
}

pub fn log_info(message: String) {
    _log("info".to_string(), message, "rust".to_string());
}

pub fn log_warn(message: String) {
    _log("warn".to_string(), message, "rust".to_string());
}

pub fn log_error(message: String) {
    _log("error".to_string(), message, "rust".to_string());
}

pub fn _log(level: String, message: String, tag: String) {
    let entry = LogEntry {
        level: level.to_string(),
        message,
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64,
        tag,
    };
    let sink = LOG_STREAM_SINK.get().unwrap();
    let _ = sink.add(entry);
}
