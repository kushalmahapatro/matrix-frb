use flutter_rust_bridge::frb;
use std::sync::Mutex;
use std::{
    sync::{
        mpsc::{self, Receiver},
        Arc,
    },
    time::Duration,
};
use tokio::{
    spawn,
    task::{spawn_blocking, JoinHandle},
    time::sleep,
};

const MESSAGE_DURATION: Duration = Duration::from_secs(4);

#[frb(ignore)]
pub struct Status {
    /// Content of the latest status message, if set.
    last_status_message: Arc<Mutex<Option<String>>>,

    /// An [mpsc::Sender] that other widgets can use to change the status
    /// message.
    message_sender: mpsc::Sender<String>,

    /// The task listening for status messages to be received over the
    /// [mpsc::Receiver].
    _receiver_task: JoinHandle<()>,
}

/// A handle to the [`Status`] widget, this handle can be moved to different
/// threads where it can be used to set the status message.
#[frb(ignore)]
#[derive(Clone)]
pub struct StatusHandle {
    message_sender: mpsc::Sender<String>,
}

impl StatusHandle {
    /// Set the current status message (displayed at the bottom), for a few
    /// seconds.
    pub fn set_message(&self, status: String) {
        self.message_sender.send(status).expect(
            "We should be able to send the status message since the receiver is alive \
                  as long as we are alive",
        );
    }
}

#[frb(ignore)]
impl Clone for Status {
    fn clone(&self) -> Self {
        // Create a new Status instance rather than cloning the task
        Self::new()
    }
}

#[frb(ignore)]
impl Status {
    /// Create a new empty [`Status`] widget.
    pub fn new() -> Self {
        let (message_sender, receiver) = mpsc::channel();
        let last_status_message = Arc::new(Mutex::new(None));

        let receiver_task = spawn_blocking({
            let last_status_message = last_status_message.clone();
            move || Self::receiving_task(receiver, last_status_message)
        });

        Self {
            last_status_message,
            _receiver_task: receiver_task,
            message_sender,
        }
    }

    fn receiving_task(receiver: Receiver<String>, status_message: Arc<Mutex<Option<String>>>) {
        let mut clear_message_task: Option<JoinHandle<()>> = None;

        while let Ok(message) = receiver.recv() {
            if let Some(task) = clear_message_task.take() {
                task.abort();
            }

            {
                let mut status_message = status_message.lock().unwrap();
                *status_message = Some(message);
            }

            clear_message_task = Some(spawn({
                let status_message = status_message.clone();

                async move {
                    // Clear the status message after the standard duration.
                    sleep(MESSAGE_DURATION).await;
                    status_message.lock().unwrap().take();
                }
            }));
        }
    }

    /// Set the current status message (displayed at the bottom), for a few
    /// seconds.
    pub fn set_message(&self, status: String) {
        self.message_sender.send(status).expect(
            "We should be able to send the status message since the receiver is alive \
                  as long as we are alive",
        );
    }

    /// Get a handle to the [`Status`] widget, this can be used to set the
    /// status message from a separate thread.
    pub fn handle(&self) -> StatusHandle {
        StatusHandle {
            message_sender: self.message_sender.clone(),
        }
    }
}
