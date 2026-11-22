use std::fs;

fn parent_of(process: u32) -> Option<u32> {
	let status = fs::read_to_string(format!("/proc/{process}/status")).ok()?;
	status.lines().find_map(|line| line.strip_prefix("PPid:")).and_then(|parent| parent.trim().parse().ok())
}

pub fn ancestors(depth: usize) -> Vec<u32> {
	let mut ancestors = Vec::new();
	let mut process = std::os::unix::process::parent_id();
	while ancestors.len() < depth && process > 1 {
		ancestors.push(process);
		match parent_of(process) {
			Some(parent) => process = parent,
			None => break,
		}
	}
	ancestors
}

pub fn arguments_of(process: u32) -> Option<Vec<String>> {
	let command_line = fs::read(format!("/proc/{process}/cmdline")).ok()?;
	Some(
		command_line
			.split(|&byte| byte == 0)
			.filter(|argument| !argument.is_empty())
			.map(|argument| String::from_utf8_lossy(argument).into_owned())
			.collect(),
	)
}
