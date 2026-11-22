pub enum Request {
	Push { repository: String, destination: Option<String>, commits: Option<u32> },
	Fetch { repository: String },
	Archive { repository: String },
	Lfs { repository: String, upload: bool },
	Sign { repository: String, branch: Option<String>, tag: Option<String>, subject: Option<String> },
}
