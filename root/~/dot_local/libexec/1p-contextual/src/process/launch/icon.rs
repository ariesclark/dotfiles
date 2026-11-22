const HEADER: usize = 6;
const ENTRY: usize = 14;
const IDENTIFIER: usize = 12;

fn renumbered(group: &[u8]) -> Option<(Vec<u8>, Vec<u16>)> {
	let count = usize::from(u16::from_le_bytes([*group.get(4)?, *group.get(5)?]));
	if count == 0 || group.len() < HEADER + ENTRY * count {
		return None;
	}
	let mut renumbered = group[..HEADER + ENTRY * count].to_vec();
	let mut images = Vec::with_capacity(count);
	for (index, entry) in renumbered[HEADER..].chunks_exact_mut(ENTRY).enumerate() {
		images.push(u16::from_le_bytes([entry[IDENTIFIER], entry[IDENTIFIER + 1]]));
		entry[IDENTIFIER..].copy_from_slice(&(index as u16 + 1).to_le_bytes());
	}
	Some((renumbered, images))
}

#[cfg(windows)]
pub use windows::borrow;

#[cfg(windows)]
mod windows {
	use std::ffi::{c_void, OsStr};
	use std::io;
	use std::os::windows::ffi::OsStrExt;
	use std::path::Path;
	use std::{ptr, slice};

	use windows_sys::core::PCWSTR;
	use windows_sys::Win32::Foundation::{FreeLibrary, BOOL, FALSE, HMODULE, TRUE};
	use windows_sys::Win32::System::LibraryLoader::{
		BeginUpdateResourceW, EndUpdateResourceW, EnumResourceNamesW, FindResourceW, LoadLibraryExW, LoadResource, LockResource, SizeofResource, UpdateResourceW,
		LOAD_LIBRARY_AS_DATAFILE, LOAD_LIBRARY_AS_IMAGE_RESOURCE,
	};

	const ICON: u16 = 3;
	const GROUP_ICON: u16 = 14;

	struct Icon {
		group: Vec<u8>,
		images: Vec<Vec<u8>>,
	}

	fn wide(text: &OsStr) -> Vec<u16> {
		text.encode_wide().chain([0]).collect()
	}

	fn resource(module: HMODULE, name: PCWSTR, kind: u16) -> Option<Vec<u8>> {
		let found = unsafe { FindResourceW(module, name, kind as usize as PCWSTR) };
		if found.is_null() {
			return None;
		}
		let size = unsafe { SizeofResource(module, found) } as usize;
		let data = unsafe { LockResource(LoadResource(module, found)) } as *const u8;
		(!data.is_null() && size > 0).then(|| unsafe { slice::from_raw_parts(data, size) }.to_vec())
	}

	unsafe extern "system" fn first_icon(module: HMODULE, _kind: PCWSTR, name: PCWSTR, found: isize) -> BOOL {
		let found = unsafe { &mut *(found as *mut Option<Icon>) };
		let icon = resource(module, name, GROUP_ICON).and_then(|group| super::renumbered(&group)).and_then(|(group, identifiers)| {
			let images = identifiers.into_iter().map(|identifier| resource(module, identifier as usize as PCWSTR, ICON)).collect::<Option<Vec<_>>>()?;
			Some(Icon { group, images })
		});
		*found = icon;
		FALSE
	}

	fn icon_of(executable: &Path) -> Option<Icon> {
		let path = wide(executable.as_os_str());
		let module = unsafe { LoadLibraryExW(path.as_ptr(), ptr::null_mut(), LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE) };
		if module.is_null() {
			return None;
		}
		let mut found: Option<Icon> = None;
		unsafe { EnumResourceNamesW(module, GROUP_ICON as usize as PCWSTR, Some(first_icon), &mut found as *mut Option<Icon> as isize) };
		unsafe { FreeLibrary(module) };
		found
	}

	fn update_error(action: &str) -> io::Error {
		let error = io::Error::last_os_error();
		io::Error::new(error.kind(), format!("could not {action} the icon of the named copy: {error}"))
	}

	pub fn borrow(application: &Path, copy: &Path) -> io::Result<()> {
		let Some(icon) = icon_of(application) else { return Ok(()) };
		let path = wide(copy.as_os_str());
		let update = unsafe { BeginUpdateResourceW(path.as_ptr(), TRUE) };
		if update.is_null() {
			return Err(update_error("open"));
		}
		let resources = icon.images.iter().enumerate().map(|(index, image)| (ICON, index as u16 + 1, image)).chain([(GROUP_ICON, 1, &icon.group)]);
		for (kind, name, data) in resources {
			if unsafe { UpdateResourceW(update, kind as usize as PCWSTR, name as usize as PCWSTR, 0, data.as_ptr() as *const c_void, data.len() as u32) } == 0 {
				let error = update_error("write");
				unsafe { EndUpdateResourceW(update, TRUE) };
				return Err(error);
			}
		}
		if unsafe { EndUpdateResourceW(update, FALSE) } == 0 {
			return Err(update_error("save"));
		}
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn group(identifiers: &[u16]) -> Vec<u8> {
		let mut group = vec![0, 0, 1, 0];
		group.extend((identifiers.len() as u16).to_le_bytes());
		for (index, identifier) in identifiers.iter().enumerate() {
			group.extend([16 * (index as u8 + 1), 16 * (index as u8 + 1), 0, 0, 1, 0, 32, 0]);
			group.extend((100 + index as u32).to_le_bytes());
			group.extend(identifier.to_le_bytes());
		}
		group
	}

	#[test]
	fn numbers_the_images_from_one_and_returns_their_old_numbers() {
		assert_eq!(renumbered(&group(&[7, 42, 3])), Some((group(&[1, 2, 3]), vec![7, 42, 3])));
	}

	#[test]
	fn refuses_a_group_shorter_than_its_count_says() {
		let mut short = group(&[7, 42]);
		short.truncate(short.len() - 1);
		assert_eq!(renumbered(&short), None);
	}

	#[test]
	fn refuses_a_group_without_images() {
		assert_eq!(renumbered(&group(&[])), None);
		assert_eq!(renumbered(&[0, 0, 1]), None);
	}
}
