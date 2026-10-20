Set-StrictMode -Version Latest

if (-not ('ShellShortcut' -as [type])) {
	Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

public static class ShellShortcut {
	[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
	class ShellLink {}

	[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
	interface IShellLinkW {
		void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int size, IntPtr findData, uint flags);
		void GetIDList(out IntPtr list);
		void SetIDList(IntPtr list);
		void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int size);
		void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
		void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder directory, int size);
		void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
		void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int size);
		void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
		void GetHotkey(out short key);
		void SetHotkey(short key);
		void GetShowCmd(out int command);
		void SetShowCmd(int command);
		void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int size, out int index);
		void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
		void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
		void Resolve(IntPtr window, uint flags);
		void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
	}

	[StructLayout(LayoutKind.Sequential)]
	struct PropertyKey { public Guid FormatId; public int PropertyId; }

	[StructLayout(LayoutKind.Sequential)]
	struct PropVariant { public ushort Type; public ushort Reserved1, Reserved2, Reserved3; public IntPtr Pointer; public IntPtr Extra; }

	[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
	interface IPropertyStore {
		void GetCount(out uint count);
		void GetAt(uint index, out PropertyKey key);
		void GetValue(ref PropertyKey key, out PropVariant value);
		void SetValue(ref PropertyKey key, ref PropVariant value);
		void Commit();
	}

	const ushort StringType = 31;
	const uint RawPath = 4;
	static PropertyKey appIdKey = new PropertyKey { FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), PropertyId = 5 };

	public static void Write(string path, string target, string arguments, string appId) {
		var link = (IShellLinkW)new ShellLink();
		link.SetPath(target);
		link.SetArguments(arguments);
		link.SetWorkingDirectory(System.IO.Path.GetDirectoryName(target));
		if (!string.IsNullOrEmpty(appId)) {
			var value = new PropVariant { Type = StringType, Pointer = Marshal.StringToCoTaskMemUni(appId) };
			try {
				var store = (IPropertyStore)link;
				store.SetValue(ref appIdKey, ref value);
				store.Commit();
			}
			finally {
				Marshal.FreeCoTaskMem(value.Pointer);
			}
		}
		((IPersistFile)link).Save(path, true);
	}

	public static string[] Read(string path) {
		var link = (IShellLinkW)new ShellLink();
		((IPersistFile)link).Load(path, 0);
		var target = new StringBuilder(1024);
		link.GetPath(target, target.Capacity, IntPtr.Zero, RawPath);
		var arguments = new StringBuilder(4096);
		link.GetArguments(arguments, arguments.Capacity);
		PropVariant value;
		((IPropertyStore)link).GetValue(ref appIdKey, out value);
		var appId = value.Type == StringType ? Marshal.PtrToStringUni(value.Pointer) : null;
		return new[] { target.ToString(), arguments.ToString(), appId };
	}
}
'@
}

function Get-Shortcut {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [string] $Path)

	$target, $arguments, $appId = [ShellShortcut]::Read($Path)
	[pscustomobject]@{ Target = $target; Arguments = $arguments; AppId = $appId }
}

function Sync-Shortcut {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Path,
		[Parameter(Mandatory)] [string] $Target,
		[Parameter(Mandatory)] [AllowEmptyString()] [string] $Arguments,
		[Parameter(Mandatory)] [AllowEmptyString()] [string] $AppId
	)

	if (Test-Path -LiteralPath $Path) {
		$current = Get-Shortcut -Path $Path
		if ($current.Target -eq $Target -and $current.Arguments -eq $Arguments -and "$($current.AppId)" -eq $AppId) {
			return
		}
	}
	[ShellShortcut]::Write($Path, $Target, $Arguments, $AppId)
}

Export-ModuleMember -Function Get-Shortcut, Sync-Shortcut
