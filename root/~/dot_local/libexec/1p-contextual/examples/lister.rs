use std::{env, fs, path::Path, thread, time::Duration};

fn collect_file_names(directory: &Path, names: &mut Vec<String>) {
	let Ok(entries) = fs::read_dir(directory) else { return };
	for entry in entries.flatten() {
		let path = entry.path();
		if path.is_dir() {
			collect_file_names(&path, names);
		} else {
			names.push(entry.file_name().to_string_lossy().into_owned());
		}
	}
}

fn main() {
	if let Some(started) = env::var_os("CONTEXTUAL_STARTED") {
		fs::write(started, std::process::id().to_string()).expect("the start marker should be writable");
	}
	if let Some(seconds) = env::var("CONTEXTUAL_LINGER").ok().and_then(|seconds| seconds.parse().ok()) {
		thread::sleep(Duration::from_secs(seconds));
	}
	let mut names = Vec::new();
	collect_file_names(&env::temp_dir().join("1p-contextual"), &mut names);
	if let Some(listing) = env::var_os("CONTEXTUAL_LISTING") {
		fs::write(listing, names.join("\n")).expect("the listing should be writable");
	}
	if let Some(recording) = env::var_os("CONTEXTUAL_ARGUMENTS") {
		let arguments: Vec<String> = env::args().skip(1).collect();
		fs::write(recording, arguments.join("\n")).expect("the arguments should be writable");
	}
	std::process::exit(3);
}
