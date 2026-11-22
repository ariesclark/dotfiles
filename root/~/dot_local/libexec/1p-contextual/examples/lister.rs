use std::path::{Path, PathBuf};
use std::{env, fs, thread, time::Duration};

fn collect_files(directory: &Path, files: &mut Vec<PathBuf>) {
	let Ok(entries) = fs::read_dir(directory) else { return };
	for entry in entries.flatten() {
		let path = entry.path();
		if path.is_dir() {
			collect_files(&path, files);
		} else {
			files.push(path);
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
	let mut files = Vec::new();
	collect_files(&env::temp_dir().join("1p-contextual"), &mut files);
	if let Some(listing) = env::var_os("CONTEXTUAL_LISTING") {
		let names: Vec<String> = files.iter().map(|file| file.file_name().unwrap_or_default().to_string_lossy().into_owned()).collect();
		fs::write(listing, names.join("\n")).expect("the listing should be writable");
	}
	if let Some(kept) = env::var_os("CONTEXTUAL_KEEP") {
		fs::create_dir_all(&kept).expect("the folder for kept copies should be creatable");
		for file in &files {
			fs::copy(file, Path::new(&kept).join(file.file_name().unwrap_or_default())).expect("the copy should be keepable");
		}
	}
	if let Some(recording) = env::var_os("CONTEXTUAL_ARGUMENTS") {
		let arguments: Vec<String> = env::args().skip(1).collect();
		fs::write(recording, arguments.join("\n")).expect("the arguments should be writable");
	}
	std::process::exit(3);
}
