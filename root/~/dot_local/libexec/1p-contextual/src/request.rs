#[derive(Debug, PartialEq)]
pub enum Update {
	Branch(String),
	Tag(String),
	AllBranches,
	Everything,
	AllTags,
}

#[derive(Debug, PartialEq)]
pub enum Deletion {
	Branch(String),
	Tag(String),
}

pub enum Request {
	Push { repository: String, updates: Vec<Update>, commits: Option<u32>, deletions: Vec<Deletion> },
	Fetch { repository: String },
	Archive { repository: String },
	Lfs { repository: String, upload: bool },
	Sign { repository: String, branch: Option<String>, tag: Option<String>, subject: Option<String> },
}
