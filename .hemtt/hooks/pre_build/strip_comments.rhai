// Strips every comment from the copies of the source that get packed, so the
// mod ships without them while the files in the repo keep theirs.
//
// Only the build's virtual file system (HEMTT_VFS) is written: nothing on disk
// changes. Line breaks inside a removed block comment are kept, so a line
// number in an RPT error is the same line in the repo's file.
//
// To pack the comments again, delete this file.

fn strip_comments(src) {
    let chars = src.to_chars();
    let n = chars.len();
    let out = "";
    let i = 0;
    while i < n {
        let c = chars[i];
        if c == '"' || c == '\'' {
            // A string, to its closing quote (a doubled quote is one inside it).
            out += c;
            i += 1;
            while i < n {
                let d = chars[i];
                out += d;
                i += 1;
                if d == c {
                    if i < n && chars[i] == c {
                        out += c;
                        i += 1;
                    } else {
                        break;
                    }
                }
            }
        } else if c == '/' && i + 1 < n && chars[i + 1] == '*' {
            i += 2;
            while i < n {
                if chars[i] == '*' && i + 1 < n && chars[i + 1] == '/' {
                    i += 2;
                    break;
                }
                if chars[i] == '\n' {
                    out += "\n";
                }
                i += 1;
            }
        } else if c == '/' && i + 1 < n && chars[i + 1] == '/' {
            while i < n && chars[i] != '\n' {
                i += 1;
            }
        } else {
            out += c;
            i += 1;
        }
    }
    out
}

fn strip_dir(dir) {
    let count = 0;
    for entry in dir.list() {
        if entry.is_dir() {
            count += strip_dir(entry);
        } else {
            let name = entry.file_name();
            if name.ends_with(".sqf") || name.ends_with(".hpp") || name.ends_with(".cpp") {
                let src = entry.open_file().read();
                let stripped = strip_comments(src);
                if stripped.len() != src.len() {
                    entry.create_file().write(stripped);
                    count += 1;
                }
            }
        }
    }
    count
}

let files = strip_dir(HEMTT_VFS.join("addons"));
print("Stripped the comments from " + files + " packed files");
