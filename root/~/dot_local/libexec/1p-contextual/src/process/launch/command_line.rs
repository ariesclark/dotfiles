const BACKSLASH: u16 = b'\\' as u16;
const QUOTE: u16 = b'"' as u16;

pub fn quote(argument: &[u16]) -> Vec<u16> {
	let needs_quotes = argument.is_empty() || argument.iter().any(|&unit| matches!(unit, 0x20 | 0x09 | 0x0A | 0x0B) || unit == QUOTE);
	if !needs_quotes {
		return argument.to_vec();
	}
	let mut quoted = vec![QUOTE];
	let mut backslashes = 0;
	for &unit in argument {
		match unit {
			BACKSLASH => backslashes += 1,
			QUOTE => {
				quoted.extend(std::iter::repeat(BACKSLASH).take(backslashes * 2 + 1));
				quoted.push(QUOTE);
				backslashes = 0;
			}
			_ => {
				quoted.extend(std::iter::repeat(BACKSLASH).take(backslashes));
				quoted.push(unit);
				backslashes = 0;
			}
		}
	}
	quoted.extend(std::iter::repeat(BACKSLASH).take(backslashes * 2));
	quoted.push(QUOTE);
	quoted
}

pub fn join(arguments: &[&[u16]]) -> Vec<u16> {
	let mut line = Vec::new();
	for (index, argument) in arguments.iter().enumerate() {
		if index > 0 {
			line.push(b' ' as u16);
		}
		line.extend(quote(argument));
	}
	line.push(0);
	line
}

#[cfg(test)]
mod tests {
	use super::*;

	fn quoted(argument: &str) -> String {
		String::from_utf16(&quote(&argument.encode_utf16().collect::<Vec<_>>())).unwrap()
	}

	#[test]
	fn leaves_a_plain_argument_as_it_is() {
		assert_eq!(quoted("git-receive-pack"), "git-receive-pack");
		assert_eq!(quoted(r"C:\Users\aries\key.pub"), r"C:\Users\aries\key.pub");
	}

	#[test]
	fn quotes_an_empty_argument() {
		assert_eq!(quoted(""), r#""""#);
	}

	#[test]
	fn quotes_an_argument_with_whitespace() {
		assert_eq!(quoted("git-receive-pack 'owner/repo.git'"), r#""git-receive-pack 'owner/repo.git'""#);
		assert_eq!(quoted("a\tb"), "\"a\tb\"");
	}

	#[test]
	fn escapes_a_quote_and_the_backslashes_before_it() {
		assert_eq!(quoted(r#"a"b"#), r#""a\"b""#);
		assert_eq!(quoted(r#"a\"b"#), r#""a\\\"b""#);
	}

	#[test]
	fn doubles_the_backslashes_before_the_closing_quote() {
		assert_eq!(quoted(r"a b\"), r#""a b\\""#);
		assert_eq!(quoted(r"C:\Program Files\"), r#""C:\Program Files\\""#);
	}

	#[test]
	fn joins_quoted_arguments_into_a_terminated_command_line() {
		let program: Vec<u16> = r"C:\Temp\a push.exe".encode_utf16().collect();
		let flag: Vec<u16> = "--supervise".encode_utf16().collect();
		let line = join(&[&program, &flag]);
		assert_eq!(String::from_utf16(&line).unwrap(), "\"C:\\Temp\\a push.exe\" --supervise\0");
	}

	#[test]
	fn keeps_backslashes_that_no_quote_follows() {
		assert_eq!(quoted(r"a\b c"), r#""a\b c""#);
	}
}
