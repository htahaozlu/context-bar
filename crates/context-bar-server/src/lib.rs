//! `context-bar-server` — self-hosted sync backend for the ContextBar
//! menubar app. See `main.rs` for the CLI entry point.
//!
//! Run the binary:
//!     $ cargo run --release -p context-bar-server

pub mod auth;
pub mod db;
pub mod http;
pub mod model;

pub mod test_support {
    //! In-process test server. Boots a `tiny_http` listener on an
    //! ephemeral port, returns the base URL + token. The server runs
    //! until the process exits — the OS reaps the listener.
    //!
    //! Used by `examples/self_test.rs`. Keeping the lifecycle simple (no
    //! shutdown signal) avoids the cross-thread socket-close race that's
    //! easy to get wrong with tiny_http's blocking accept loop.
    //!
    //! Run with:
    //!     $ cargo run --release -p context-bar-server --example self_test

    use crate::db::Db;
    use crate::http::State;
    use std::net::TcpListener;
    use std::path::PathBuf;
    use std::sync::Arc;

    pub struct Handle {
        base: String,
        token: String,
        db_path: PathBuf,
        _join: Option<std::thread::JoinHandle<()>>,
    }

    /// Bind to `127.0.0.1:0` for an ephemeral port, start the server,
    /// return the base URL + token.
    pub fn spawn(_bind: &str) -> anyhow::Result<Handle> {
        let probe = TcpListener::bind("127.0.0.1:0")?;
        let port = probe.local_addr()?.port();
        drop(probe);
        let actual = format!("127.0.0.1:{}", port);

        let mut db_path = std::env::temp_dir();
        db_path.push(format!(
            "context-bar-server-test-{}-{}.sqlite",
            std::process::id(),
            port
        ));
        let db = Arc::new(Db::open(&db_path)?);
        db.migrate()?;

        let token = format!("cbar_test_{}", random_hex(16));
        let state = State {
            db,
            token: Arc::new(token.clone()),
        };

        let base = format!("http://{}", actual);
        let actual_for_thread = actual.clone();
        let join = std::thread::spawn(move || {
            if let Ok(server) = tiny_http::Server::http(&actual_for_thread) {
                for req in server.incoming_requests() {
                    if let Err(e) = crate::http::serve_request(req, &state) {
                        log::warn!("test_support: {}", e);
                    }
                }
            }
        });

        std::thread::sleep(std::time::Duration::from_millis(50));

        Ok(Handle {
            base,
            token,
            db_path,
            _join: Some(join),
        })
    }

    impl Handle {
        pub fn base_url(&self) -> &str {
            &self.base
        }
        pub fn token(&self) -> &str {
            &self.token
        }
        pub fn db_path(&self) -> &PathBuf {
            &self.db_path
        }

        /// Best-effort cleanup of the temp DB file.
        pub fn cleanup(&self) {
            let _ = std::fs::remove_file(&self.db_path);
            for ext in ["-wal", "-shm"] {
                let p = self.db_path.with_extension(format!("sqlite{ext}"));
                let _ = std::fs::remove_file(p);
            }
        }
    }

    fn random_hex(n: usize) -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        let ns = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let pid = std::process::id() as u128;
        let mut s = String::with_capacity(n * 2);
        let mut v: u128 = ns ^ (pid.wrapping_mul(0x9E37_79B9_7F4A_7C15));
        for _ in 0..n {
            s.push_str(&format!("{:02x}", (v & 0xFF) as u8));
            v >>= 8;
        }
        s
    }
}
