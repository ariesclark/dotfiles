pub fn repository(remote: &str) -> Option<String> {
	let url = url::Url::parse(remote).ok()?;
	url.host()?;
	let path = url.path().trim_matches('/');
	let path = path.strip_suffix(".git").unwrap_or(path);
	(!path.is_empty()).then(|| path.to_string())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn takes_the_repository_from_a_url() {
		assert_eq!(repository("https://github.com/owner/repo.git"), Some("owner/repo".to_string()));
		assert_eq!(repository("ssh://git@github.com/owner/repo"), Some("owner/repo".to_string()));
	}

	#[test]
	fn takes_no_repository_from_a_remote_that_is_not_a_url() {
		assert_eq!(repository("git@github.com:owner/repo.git"), None);
		assert_eq!(repository("C:/repositories/repo"), None);
		assert_eq!(repository("../repo"), None);
	}
}
