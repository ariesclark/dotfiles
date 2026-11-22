#[derive(Debug, PartialEq)]
pub struct SignedObject<'a> {
	pub tag: Option<&'a str>,
	pub subject: Option<&'a str>,
}

pub fn read(buffer: &str) -> SignedObject<'_> {
	let mut lines = buffer.split('\n').map(|line| line.strip_suffix('\r').unwrap_or(line));
	let mut tag = None;
	for header in lines.by_ref() {
		if header.is_empty() {
			let subject = lines.next().filter(|subject| !subject.is_empty());
			return SignedObject { tag, subject };
		}
		if let Some(name) = header.strip_prefix("tag ") {
			tag = Some(name);
		}
	}
	SignedObject { tag, subject: None }
}

#[cfg(test)]
mod tests {
	use super::*;

	const COMMIT: &str = "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Stub <stub@example.com> 0 +0000\n\nfeat(git): sign it\n\nThe body.\n";
	const TAG: &str = "object 4b825dc642cb6eb9a060e54bf8d69288fbee4904\ntype commit\ntag v1\ntagger Stub <stub@example.com> 0 +0000\n\nrelease it\n";

	#[test]
	fn reads_the_subject_of_a_commit() {
		assert_eq!(read(COMMIT), SignedObject { tag: None, subject: Some("feat(git): sign it") });
	}

	#[test]
	fn reads_a_commit_with_windows_line_endings() {
		assert_eq!(read(&COMMIT.replace('\n', "\r\n")), SignedObject { tag: None, subject: Some("feat(git): sign it") });
	}

	#[test]
	fn reads_the_name_and_subject_of_a_tag() {
		assert_eq!(read(TAG), SignedObject { tag: Some("v1"), subject: Some("release it") });
	}

	#[test]
	fn reads_no_subject_from_an_object_without_a_message() {
		assert_eq!(read("certificate version 0.1\npusher x\n"), SignedObject { tag: None, subject: None });
		assert_eq!(read("tree x\n\n"), SignedObject { tag: None, subject: None });
	}
}
