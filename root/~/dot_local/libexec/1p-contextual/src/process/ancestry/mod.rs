#[cfg(unix)]
mod linux;
#[cfg(windows)]
mod windows;

#[cfg(unix)]
use linux as platform;
#[cfg(windows)]
use windows as platform;

const SEARCH_DEPTH: usize = 4;

pub fn find<T>(recognize: impl Fn(&[String]) -> Option<T>) -> Option<T> {
	platform::ancestors(SEARCH_DEPTH)
		.into_iter()
		.find_map(|process| platform::arguments_of(process).as_deref().and_then(&recognize))
}
