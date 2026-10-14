//! Mac Initial Setup – desktop front-end.
//!
//! A native window with a web view (WKWebView) showing the checklist. The real work is
//! done by the bash engine (`setup.sh --gui-run`), which reports progress as
//! `::event::payload` lines on stdout and reads answers to questions from stdin.

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

use serde_json::{json, Value};
use tao::dpi::LogicalSize;
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy};
use tao::platform::macos::{ActivationPolicy, EventLoopExtMacOS};
use tao::window::WindowBuilder;
use wry::WebViewBuilder;

const INDEX_HTML: &str = include_str!("../ui/index.html");
const VERSION: &str = env!("CARGO_PKG_VERSION");

enum UserEvent {
    /// JavaScript to run in the web view.
    Js(String),
}

#[derive(Default)]
struct State {
    stdin: Option<ChildStdin>,
    secrets: Option<PathBuf>,
    running: bool,
}

type Shared = Arc<Mutex<State>>;

fn main() {
    let root = find_root().unwrap_or_else(|| {
        eprintln!("Could not find setup.sh. Set MAC_SETUP_ROOT to the repository folder.");
        std::process::exit(1);
    });
    let dry_default = std::env::args().any(|a| a == "--dry-run" || a == "-n");

    let mut event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    event_loop.set_activation_policy(ActivationPolicy::Regular);
    let proxy = event_loop.create_proxy();

    let window = WindowBuilder::new()
        .with_title("Mac Initial Setup")
        .with_inner_size(LogicalSize::new(1180.0, 820.0))
        .with_min_inner_size(LogicalSize::new(860.0, 600.0))
        .build(&event_loop)
        .expect("window");

    let state: Shared = Arc::default();
    let ipc_state = state.clone();
    let ipc_proxy = proxy.clone();
    let ipc_root = root.clone();

    let webview = WebViewBuilder::new()
        .with_html(INDEX_HTML)
        .with_ipc_handler(move |req| {
            let msg: Value = serde_json::from_str(req.body()).unwrap_or(Value::Null);
            handle_ipc(&msg, &ipc_root, &ipc_proxy, &ipc_state, dry_default);
        })
        // Links open in the default browser, never inside the app.
        .with_navigation_handler(|url| {
            if url.starts_with("http") {
                let _ = Command::new("open").arg(&url).spawn();
                return false;
            }
            true
        })
        .with_new_window_req_handler(|url, _| {
            let _ = Command::new("open").arg(&url).spawn();
            wry::NewWindowResponse::Deny
        })
        .build(&window)
        .expect("webview");

    window.set_focus();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            Event::UserEvent(UserEvent::Js(js)) => {
                let _ = webview.evaluate_script(&js);
            }
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                cleanup(&state);
                *control_flow = ControlFlow::Exit;
            }
            _ => {}
        }
    });
}

/// The folder that contains setup.sh: $MAC_SETUP_ROOT, next to or above the binary, or the cwd.
fn find_root() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(r) = std::env::var("MAC_SETUP_ROOT") {
        candidates.push(PathBuf::from(r));
    }
    if let Ok(exe) = std::env::current_exe() {
        candidates.extend(exe.ancestors().skip(1).take(4).map(Path::to_path_buf));
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.extend(cwd.ancestors().take(2).map(Path::to_path_buf));
    }
    candidates.into_iter().find(|p| p.join("setup.sh").is_file())
}

fn call_js(proxy: &EventLoopProxy<UserEvent>, func: &str, arg: Value) {
    let _ = proxy.send_event(UserEvent::Js(format!("window.{func}({arg})")));
}

fn handle_ipc(msg: &Value, root: &Path, proxy: &EventLoopProxy<UserEvent>, state: &Shared, dry_default: bool) {
    match msg["cmd"].as_str().unwrap_or("") {
        "catalog" => {
            let (root, proxy) = (root.to_path_buf(), proxy.clone());
            thread::spawn(move || {
                let out = Command::new("/bin/bash").arg(root.join("setup.sh")).arg("--json").output();
                match out.ok().and_then(|o| serde_json::from_slice::<Value>(&o.stdout).ok()) {
                    Some(rows) => call_js(
                        &proxy,
                        "loadCatalog",
                        json!({ "rows": rows, "dryRun": dry_default, "version": VERSION, "user": whoami() }),
                    ),
                    None => call_js(&proxy, "fatal", json!("Could not read the catalog from setup.sh")),
                }
            });
        }
        "start" => start(msg, root, proxy, state),
        "answer" => {
            let mut st = state.lock().unwrap();
            if let Some(stdin) = st.stdin.as_mut() {
                let _ = writeln!(stdin, "{}", msg["value"].as_str().unwrap_or(""));
                let _ = stdin.flush();
            }
        }
        "open" => {
            if let Some(target) = msg["target"].as_str() {
                let _ = Command::new("open").arg(target).spawn();
            }
        }
        "quit" => {
            cleanup(state);
            std::process::exit(0);
        }
        _ => {}
    }
}

fn whoami() -> String {
    std::env::var("USER").unwrap_or_default()
}

/// Write the password to a private temp folder with an askpass helper that prints it.
/// sudo (and Homebrew) use it via SUDO_ASKPASS; the folder is removed afterwards.
fn write_askpass(password: &str) -> std::io::Result<PathBuf> {
    let dir = std::env::temp_dir().join(format!("mac-setup-{}", std::process::id()));
    fs::create_dir_all(&dir)?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    let pw = dir.join("pw");
    fs::write(&pw, password)?;
    fs::set_permissions(&pw, fs::Permissions::from_mode(0o600))?;
    let helper = dir.join("askpass");
    fs::write(&helper, format!("#!/bin/sh\ncat '{}'\necho\n", pw.display()))?;
    fs::set_permissions(&helper, fs::Permissions::from_mode(0o700))?;
    Ok(dir)
}

fn password_ok(askpass: &Path) -> bool {
    Command::new("/usr/bin/sudo")
        .args(["-A", "-v"])
        .env("SUDO_ASKPASS", askpass)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn start(msg: &Value, root: &Path, proxy: &EventLoopProxy<UserEvent>, state: &Shared) {
    if state.lock().unwrap().running {
        return;
    }
    let ids: Vec<String> = msg["ids"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let dry_run = msg["dryRun"].as_bool().unwrap_or(false);
    let password = msg["password"].as_str().unwrap_or("").to_string();

    let mut cmd = Command::new("/bin/bash");
    cmd.arg(root.join("setup.sh")).arg("--gui-run").arg("--only").arg(ids.join(","));
    if dry_run {
        cmd.arg("--dry-run");
    }
    if let Some(settings) = msg["settings"].as_object() {
        for (key, value) in settings {
            cmd.env(format!("MAC_SETUP_{}", key.to_uppercase()), value.as_str().unwrap_or(""));
        }
    }
    cmd.env("MAC_SETUP_GUI", "1")
        .current_dir(root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let (root, proxy, state) = (root.to_path_buf(), proxy.clone(), state.clone());
    thread::spawn(move || {
        if !dry_run {
            let dir = match write_askpass(&password) {
                Ok(d) => d,
                Err(e) => return call_js(&proxy, "startFailed", json!(format!("Could not prepare sudo: {e}"))),
            };
            state.lock().unwrap().secrets = Some(dir.clone());
            let helper = dir.join("askpass");
            if !password_ok(&helper) {
                cleanup(&state);
                return call_js(&proxy, "startFailed", json!("That password is not correct."));
            }
            cmd.env("SUDO_ASKPASS", &helper);
        }
        let _ = root;
        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => return call_js(&proxy, "startFailed", json!(format!("Could not start setup.sh: {e}"))),
        };
        {
            let mut st = state.lock().unwrap();
            st.stdin = child.stdin.take();
            st.running = true;
        }
        call_js(&proxy, "started", json!(null));

        let stderr = child.stderr.take().unwrap();
        let err_proxy = proxy.clone();
        let err_thread = thread::spawn(move || pump(stderr, &err_proxy));
        pump(child.stdout.take().unwrap(), &proxy);
        let _ = err_thread.join();

        let code = child.wait().map(|s| s.code().unwrap_or(-1)).unwrap_or(-1);
        {
            let mut st = state.lock().unwrap();
            st.stdin = None;
            st.running = false;
        }
        cleanup(&state);
        call_js(&proxy, "engineExit", json!(code));
    });
}

/// Forward every output line to the UI, batched a little so a chatty brew doesn't flood it.
fn pump(stream: impl Read, proxy: &EventLoopProxy<UserEvent>) {
    let reader = BufReader::new(stream);
    for line in reader.split(b'\n').map_while(Result::ok) {
        let text = String::from_utf8_lossy(&line).replace('\r', "");
        call_js(proxy, "engineLine", json!(strip_ansi(&text)));
    }
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                while let Some(&n) = chars.peek() {
                    chars.next();
                    if n.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

fn cleanup(state: &Shared) {
    if let Some(dir) = state.lock().unwrap().secrets.take() {
        let _ = fs::remove_dir_all(dir);
    }
}
