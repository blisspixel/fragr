//! Third-party license notices for a packaged fragr-server.
//!
//! The input is `cargo metadata` JSON. Only registry crates reached from the
//! root package through normal (linked) dependencies are listed; workspace
//! crates are fragr itself and ship under the root `LICENSE`. Every listed crate
//! must carry a license expression that the cargo-deny allowlist satisfies, and
//! either its own license files or a standard text for each license it names.
//! Standard texts under `texts/` come from spdx/license-list-data v3.29.0.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

/// One distributed crate and where its source lives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Crate {
    pub name: String,
    pub version: String,
    pub license: Option<String>,
    pub license_file: Option<PathBuf>,
    pub dir: PathBuf,
}

/// Registry crates reached from `root` through normal dependencies.
pub fn distributed_crates(metadata: &Value, root: &str) -> Result<Vec<Crate>, String> {
    let packages = metadata["packages"]
        .as_array()
        .ok_or("metadata has no packages")?;
    let nodes = metadata["resolve"]["nodes"]
        .as_array()
        .ok_or("metadata has no resolve graph")?;
    let by_id: BTreeMap<&str, &Value> = packages
        .iter()
        .filter_map(|p| Some((p["id"].as_str()?, p)))
        .collect();
    let graph: BTreeMap<&str, &Value> = nodes
        .iter()
        .filter_map(|n| Some((n["id"].as_str()?, n)))
        .collect();
    let root_id = packages
        .iter()
        .find(|p| p["name"] == root && p["source"].is_null())
        .and_then(|p| p["id"].as_str())
        .ok_or_else(|| format!("workspace package {root} not found"))?;
    let mut seen = BTreeSet::from([root_id]);
    let mut stack = vec![root_id];
    while let Some(id) = stack.pop() {
        let node = graph
            .get(id)
            .ok_or_else(|| format!("{id} is missing from the resolve graph"))?;
        for dep in node["deps"].as_array().into_iter().flatten() {
            let linked = dep["dep_kinds"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|kind| kind["kind"].is_null());
            if let (true, Some(pkg)) = (linked, dep["pkg"].as_str()) {
                if seen.insert(pkg) {
                    stack.push(pkg);
                }
            }
        }
    }
    let mut out = Vec::new();
    for id in seen {
        let package = by_id
            .get(id)
            .ok_or_else(|| format!("{id} is missing from packages"))?;
        if package["source"].is_null() {
            continue;
        }
        let manifest = package["manifest_path"]
            .as_str()
            .ok_or_else(|| format!("{id} has no manifest path"))?;
        let dir = Path::new(manifest)
            .parent()
            .ok_or_else(|| format!("{id} has no source directory"))?
            .to_path_buf();
        out.push(Crate {
            name: package["name"].as_str().unwrap_or_default().to_string(),
            version: package["version"].as_str().unwrap_or_default().to_string(),
            license: package["license"].as_str().map(str::to_string),
            license_file: package["license_file"].as_str().map(|file| dir.join(file)),
            dir,
        });
    }
    out.sort_by(|a, b| (&a.name, &a.version).cmp(&(&b.name, &b.version)));
    Ok(out)
}

/// The `[licenses] allow` list from deny.toml. Only that one string array is read.
pub fn parse_allowlist(deny_toml: &str) -> Result<Vec<String>, String> {
    let mut in_licenses = false;
    let mut collecting = false;
    let mut out = Vec::new();
    for raw in deny_toml.lines() {
        let line = raw.split('#').next().unwrap_or_default().trim();
        if line.starts_with('[') && !collecting {
            in_licenses = line == "[licenses]";
            continue;
        }
        let mut rest = line;
        if in_licenses && !collecting {
            if let Some(value) = line
                .strip_prefix("allow")
                .map(str::trim_start)
                .and_then(|v| v.strip_prefix('='))
            {
                rest = value
                    .trim_start()
                    .strip_prefix('[')
                    .ok_or("allow is not an array")?;
                collecting = true;
            } else {
                continue;
            }
        }
        if collecting {
            let (items, closed) = match rest.split_once(']') {
                Some((items, _)) => (items, true),
                None => (rest, false),
            };
            for item in items
                .split(',')
                .map(str::trim)
                .filter(|item| !item.is_empty())
            {
                let value = item
                    .strip_prefix('"')
                    .and_then(|v| v.strip_suffix('"'))
                    .ok_or_else(|| format!("unquoted allow entry {item}"))?;
                out.push(value.to_string());
            }
            if closed {
                return if out.is_empty() {
                    Err("the allow list is empty".into())
                } else {
                    Ok(out)
                };
            }
        }
    }
    Err("no [licenses] allow list found".into())
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Expr {
    License(String, Option<String>),
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
}

fn tokens(expression: &str) -> Vec<String> {
    // Older crates write "MIT/Apache-2.0" for a choice.
    let spaced = expression
        .replace('(', " ( ")
        .replace(')', " ) ")
        .replace('/', " OR ");
    spaced.split_whitespace().map(str::to_string).collect()
}

struct Parser {
    tokens: Vec<String>,
    at: usize,
}

impl Parser {
    fn peek(&self) -> Option<&str> {
        self.tokens.get(self.at).map(String::as_str)
    }

    fn next(&mut self) -> Result<String, String> {
        let token = self
            .tokens
            .get(self.at)
            .cloned()
            .ok_or("expression ends early")?;
        self.at += 1;
        Ok(token)
    }

    fn or(&mut self) -> Result<Expr, String> {
        let mut left = self.and()?;
        while self.peek() == Some("OR") {
            self.at += 1;
            left = Expr::Or(Box::new(left), Box::new(self.and()?));
        }
        Ok(left)
    }

    fn and(&mut self) -> Result<Expr, String> {
        let mut left = self.atom()?;
        while self.peek() == Some("AND") {
            self.at += 1;
            left = Expr::And(Box::new(left), Box::new(self.atom()?));
        }
        Ok(left)
    }

    fn atom(&mut self) -> Result<Expr, String> {
        let token = self.next()?;
        if token == "(" {
            let inner = self.or()?;
            return if self.next()? == ")" {
                Ok(inner)
            } else {
                Err("unbalanced parenthesis".into())
            };
        }
        if matches!(token.as_str(), ")" | "AND" | "OR" | "WITH") {
            return Err(format!("unexpected {token}"));
        }
        let id = token.trim_end_matches('+').to_string();
        if self.peek() == Some("WITH") {
            self.at += 1;
            return Ok(Expr::License(id, Some(self.next()?)));
        }
        Ok(Expr::License(id, None))
    }
}

fn parse(expression: &str) -> Result<Expr, String> {
    let mut parser = Parser {
        tokens: tokens(expression),
        at: 0,
    };
    let expr = parser.or()?;
    match parser.peek() {
        None => Ok(expr),
        Some(extra) => Err(format!("unexpected {extra}")),
    }
}

fn allowed(expr: &Expr, allow: &[String]) -> bool {
    match expr {
        Expr::License(id, None) => allow.iter().any(|a| a == id),
        Expr::License(id, Some(exception)) => {
            allow.iter().any(|a| *a == format!("{id} WITH {exception}"))
        }
        Expr::And(a, b) => allowed(a, allow) && allowed(b, allow),
        Expr::Or(a, b) => allowed(a, allow) || allowed(b, allow),
    }
}

fn ids(expr: &Expr, out: &mut BTreeSet<String>) {
    match expr {
        Expr::License(id, exception) => {
            out.insert(id.clone());
            out.extend(exception.iter().cloned());
        }
        Expr::And(a, b) | Expr::Or(a, b) => {
            ids(a, out);
            ids(b, out);
        }
    }
}

/// True when the allowlist satisfies the expression, as cargo-deny would.
pub fn expression_allowed(expression: &str, allow: &[String]) -> Result<bool, String> {
    Ok(allowed(&parse(expression)?, allow))
}

/// Every license and exception id an expression names.
pub fn license_ids(expression: &str) -> Result<BTreeSet<String>, String> {
    let mut out = BTreeSet::new();
    ids(&parse(expression)?, &mut out);
    Ok(out)
}

/// The SPDX standard text for an id, when this tool carries one.
pub fn standard_text(id: &str) -> Option<&'static str> {
    Some(match id {
        "0BSD" => include_str!("../texts/0BSD.txt"),
        "Apache-2.0" => include_str!("../texts/Apache-2.0.txt"),
        "BSD-2-Clause" => include_str!("../texts/BSD-2-Clause.txt"),
        "BSD-3-Clause" => include_str!("../texts/BSD-3-Clause.txt"),
        "BSL-1.0" => include_str!("../texts/BSL-1.0.txt"),
        "CC0-1.0" => include_str!("../texts/CC0-1.0.txt"),
        "CDLA-Permissive-2.0" => include_str!("../texts/CDLA-Permissive-2.0.txt"),
        "ISC" => include_str!("../texts/ISC.txt"),
        "LLVM-exception" => include_str!("../texts/LLVM-exception.txt"),
        "MIT" => include_str!("../texts/MIT.txt"),
        "MIT-0" => include_str!("../texts/MIT-0.txt"),
        "MPL-2.0" => include_str!("../texts/MPL-2.0.txt"),
        "OpenSSL" => include_str!("../texts/OpenSSL.txt"),
        "Unicode-3.0" => include_str!("../texts/Unicode-3.0.txt"),
        "Unicode-DFS-2016" => include_str!("../texts/Unicode-DFS-2016.txt"),
        "Zlib" => include_str!("../texts/Zlib.txt"),
        _ => return None,
    })
}

/// License, notice and copying files at the top of a crate's source, plus a
/// declared `license-file` wherever it points.
pub fn license_files(krate: &Crate) -> std::io::Result<Vec<PathBuf>> {
    let mut found = BTreeSet::new();
    for entry in fs::read_dir(&krate.dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().to_ascii_uppercase();
        let named = [
            "LICENSE",
            "LICENCE",
            "COPYING",
            "COPYRIGHT",
            "NOTICE",
            "UNLICENSE",
        ]
        .iter()
        .any(|prefix| name.starts_with(prefix));
        if named && entry.file_type()?.is_file() {
            found.insert(entry.path());
        }
    }
    if let Some(declared) = &krate.license_file {
        if declared.is_file() {
            found.insert(declared.clone());
        }
    }
    Ok(found.into_iter().collect())
}

/// The notice document, or every problem that blocks it.
pub fn render(crates: &[Crate], allow: &[String]) -> Result<String, Vec<String>> {
    let mut problems = Vec::new();
    let mut sections = Vec::new();
    for krate in crates {
        let label = format!("{} {}", krate.name, krate.version);
        let Some(expression) = krate.license.as_deref().filter(|e| !e.trim().is_empty()) else {
            problems.push(format!("{label}: no SPDX license expression"));
            continue;
        };
        match expression_allowed(expression, allow) {
            Ok(true) => {}
            Ok(false) => problems.push(format!(
                "{label}: {expression} is not satisfied by the deny.toml allowlist"
            )),
            Err(error) => problems.push(format!("{label}: cannot parse {expression}: {error}")),
        }
        let files = match license_files(krate) {
            Ok(files) => files,
            Err(error) => {
                problems.push(format!(
                    "{label}: cannot read {}: {error}",
                    krate.dir.display()
                ));
                continue;
            }
        };
        let mut texts = Vec::new();
        for file in &files {
            match fs::read(file) {
                Ok(bytes) => texts.push((
                    file.file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .to_string(),
                    String::from_utf8_lossy(&bytes).into_owned(),
                )),
                Err(error) => {
                    problems.push(format!("{label}: cannot read {}: {error}", file.display()))
                }
            }
        }
        if texts.is_empty() {
            for id in license_ids(expression).unwrap_or_default() {
                match standard_text(&id) {
                    Some(text) => {
                        texts.push((format!("{id} (SPDX standard text)"), text.to_string()))
                    }
                    None => problems.push(format!(
                        "{label}: no license file and no standard text for {id}"
                    )),
                }
            }
        }
        sections.push((label, expression.to_string(), texts));
    }
    if !problems.is_empty() {
        return Err(problems);
    }
    let mut doc = String::new();
    let _ = writeln!(doc, "Third-party software in fragr-server\n");
    let _ = writeln!(
        doc,
        "fragr-server links the Rust crates below. Each is listed with its SPDX license"
    );
    let _ = writeln!(
        doc,
        "expression and the license and notice files it ships, or the SPDX standard"
    );
    let _ = writeln!(
        doc,
        "text where a crate ships none. fragr itself is under licenses/fragr-LICENSE.txt.\n"
    );
    for (label, expression, _) in &sections {
        let _ = writeln!(doc, "  {label}  ({expression})");
    }
    // Byte-identical texts (most often the Apache-2.0 file) print once. Texts
    // that differ at all, such as MIT files with their own copyright lines, stay.
    let mut printed: BTreeMap<String, String> = BTreeMap::new();
    for (label, expression, texts) in &sections {
        let _ = writeln!(doc, "\n{}\n{label}\nLicense: {expression}", "=".repeat(78));
        for (name, text) in texts {
            let body = text.replace("\r\n", "\n").trim_end().to_string();
            match printed.get(&body) {
                Some(first) => {
                    let _ = writeln!(doc, "\n--- {name} ---\n\nIdentical to {first} above.");
                }
                None => {
                    let _ = writeln!(doc, "\n--- {name} ---\n\n{body}");
                    printed.insert(body, format!("{name} of {label}"));
                }
            }
        }
    }
    Ok(doc)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn allow() -> Vec<String> {
        [
            "MIT",
            "Apache-2.0",
            "Apache-2.0 WITH LLVM-exception",
            "Unicode-3.0",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect()
    }

    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("fragr-licenses-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn krate(dir: &Path, license: Option<&str>) -> Crate {
        Crate {
            name: "demo".into(),
            version: "1.0.0".into(),
            license: license.map(str::to_string),
            license_file: None,
            dir: dir.to_path_buf(),
        }
    }

    #[test]
    fn expressions_follow_cargo_deny_choice_rules() {
        let allow = allow();
        assert!(expression_allowed("MIT OR Apache-2.0", &allow).unwrap());
        assert!(expression_allowed("Unlicense OR MIT", &allow).unwrap());
        assert!(expression_allowed("MIT/Apache-2.0", &allow).unwrap());
        assert!(expression_allowed("(MIT OR Apache-2.0) AND Unicode-3.0", &allow).unwrap());
        assert!(expression_allowed("Apache-2.0 WITH LLVM-exception", &allow).unwrap());
        assert!(expression_allowed("MIT+", &allow).unwrap());
        assert!(!expression_allowed("MIT AND GPL-3.0", &allow).unwrap());
        assert!(!expression_allowed("GPL-3.0 WITH Classpath-exception-2.0", &allow).unwrap());
        assert!(!expression_allowed("Unlicense", &allow).unwrap());
        for broken in [
            "",
            "MIT OR",
            "(MIT",
            "MIT)",
            "AND MIT",
            "MIT WITH",
            "MIT Apache-2.0",
        ] {
            assert!(
                expression_allowed(broken, &allow).is_err(),
                "{broken} should not parse"
            );
        }
        assert_eq!(
            license_ids("(MIT OR Apache-2.0 WITH LLVM-exception)").unwrap(),
            BTreeSet::from([
                "MIT".to_string(),
                "Apache-2.0".to_string(),
                "LLVM-exception".to_string()
            ])
        );
    }

    #[test]
    fn allowlist_reads_only_the_licenses_table() {
        let text = "[bans]\nallow = [\"nope\"]\n\n[licenses]\nversion = 2\nallow = [\n    \"MIT\", # comment\n    \"Apache-2.0 WITH LLVM-exception\",\n]\nconfidence = 0.8\n";
        assert_eq!(
            parse_allowlist(text).unwrap(),
            vec!["MIT", "Apache-2.0 WITH LLVM-exception"]
        );
        assert_eq!(
            parse_allowlist("[licenses]\nallow = [\"ISC\", \"Zlib\"]\n").unwrap(),
            vec!["ISC", "Zlib"]
        );
        assert!(parse_allowlist("[licenses]\nversion = 2\n").is_err());
        assert!(parse_allowlist("[licenses]\nallow = []\n").is_err());
        assert!(parse_allowlist("[licenses]\nallow = \"MIT\"\n").is_err());
        assert!(parse_allowlist("[licenses]\nallow = [MIT]\n").is_err());
        let repo = parse_allowlist(include_str!("../../../deny.toml")).unwrap();
        for id in &repo {
            let base = id.split(" WITH ").collect::<Vec<_>>();
            for part in base {
                assert!(
                    standard_text(part).is_some(),
                    "no standard text for allowlisted {part}"
                );
            }
        }
        assert!(standard_text("GPL-3.0").is_none());
    }

    #[test]
    fn graph_walk_keeps_linked_registry_crates_only() {
        let metadata = json!({
            "packages": [
                {"id": "root", "name": "fragr-server", "version": "0.1.0", "source": null, "manifest_path": "/w/server/Cargo.toml", "license": "Apache-2.0"},
                {"id": "sib", "name": "fragr-other", "version": "0.1.0", "source": null, "manifest_path": "/w/other/Cargo.toml", "license": "Apache-2.0"},
                {"id": "a", "name": "alpha", "version": "1.0.0", "source": "registry", "manifest_path": "/r/alpha/Cargo.toml", "license": "MIT", "license_file": null},
                {"id": "b", "name": "beta", "version": "2.0.0", "source": "registry", "manifest_path": "/r/beta/Cargo.toml", "license": null, "license_file": "COPYING.md"},
                {"id": "d", "name": "devonly", "version": "1.0.0", "source": "registry", "manifest_path": "/r/dev/Cargo.toml", "license": "MIT"},
                {"id": "k", "name": "buildonly", "version": "1.0.0", "source": "registry", "manifest_path": "/r/build/Cargo.toml", "license": "MIT"}
            ],
            "resolve": {"nodes": [
                {"id": "root", "deps": [
                    {"pkg": "a", "dep_kinds": [{"kind": null}]},
                    {"pkg": "sib", "dep_kinds": [{"kind": null}]},
                    {"pkg": "d", "dep_kinds": [{"kind": "dev"}]},
                    {"pkg": "k", "dep_kinds": [{"kind": "build"}]}
                ]},
                {"id": "sib", "deps": [{"pkg": "b", "dep_kinds": [{"kind": "dev"}, {"kind": null}]}]},
                {"id": "a", "deps": [{"pkg": "b", "dep_kinds": [{"kind": null}]}]},
                {"id": "b", "deps": []}, {"id": "d", "deps": []}, {"id": "k", "deps": []}
            ]}
        });
        let crates = distributed_crates(&metadata, "fragr-server").unwrap();
        let names: Vec<_> = crates.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, ["alpha", "beta"]);
        assert_eq!(crates[1].license, None);
        assert_eq!(
            crates[1].license_file,
            Some(Path::new("/r/beta").join("COPYING.md"))
        );
        assert!(distributed_crates(&metadata, "missing").is_err());
        assert!(distributed_crates(&json!({}), "fragr-server").is_err());
        assert!(distributed_crates(&json!({"packages": []}), "fragr-server").is_err());
        let orphan = json!({"packages": [{"id": "root", "name": "fragr-server", "source": null}], "resolve": {"nodes": []}});
        assert!(distributed_crates(&orphan, "fragr-server").is_err());
    }

    #[test]
    fn render_uses_crate_files_then_standard_texts() {
        let with_files = scratch("files");
        fs::write(with_files.join("LICENSE-MIT"), "MIT text from the crate\n").unwrap();
        fs::write(with_files.join("NOTICE"), "notice text\n").unwrap();
        fs::write(with_files.join("README.md"), "not a license").unwrap();
        fs::create_dir_all(with_files.join("LICENSES")).unwrap();
        let bare = scratch("bare");
        let doc = render(
            &[
                krate(&with_files, Some("MIT OR Apache-2.0")),
                Crate {
                    name: "bare".into(),
                    ..krate(&bare, Some("MIT AND Unicode-3.0"))
                },
            ],
            &allow(),
        )
        .unwrap();
        assert!(doc.contains("demo 1.0.0  (MIT OR Apache-2.0)"));
        assert!(doc.contains("--- LICENSE-MIT ---\n\nMIT text from the crate"));
        assert!(doc.contains("--- NOTICE ---"));
        assert!(!doc.contains("not a license"));
        assert!(doc.contains("--- MIT (SPDX standard text) ---"));
        assert!(doc.contains("--- Unicode-3.0 (SPDX standard text) ---"));

        let twin = scratch("twin");
        fs::write(twin.join("LICENSE-MIT"), "MIT text from the crate\r\n").unwrap();
        fs::write(twin.join("NOTICE"), "a different notice\n").unwrap();
        let doc = render(
            &[
                krate(&with_files, Some("MIT")),
                Crate {
                    name: "twin".into(),
                    ..krate(&twin, Some("MIT"))
                },
            ],
            &allow(),
        )
        .unwrap();
        assert_eq!(doc.matches("MIT text from the crate").count(), 1);
        assert!(doc.contains("Identical to LICENSE-MIT of demo 1.0.0 above."));
        assert!(doc.contains("a different notice"));
        let _ = fs::remove_dir_all(twin);

        let declared = scratch("declared");
        fs::create_dir_all(declared.join("legal")).unwrap();
        fs::write(declared.join("legal/TERMS.txt"), "declared terms\n").unwrap();
        let mut custom = krate(&declared, Some("MIT"));
        custom.license_file = Some(declared.join("legal/TERMS.txt"));
        assert!(render(&[custom], &allow())
            .unwrap()
            .contains("declared terms"));
        for dir in [with_files, bare, declared] {
            let _ = fs::remove_dir_all(dir);
        }
    }

    #[test]
    fn render_reports_every_unresolvable_crate() {
        let bare = scratch("problems");
        let missing = bare.join("gone");
        let crates = [
            krate(&bare, None),
            krate(&bare, Some("  ")),
            krate(&bare, Some("GPL-3.0")),
            krate(&bare, Some("MIT OR")),
            krate(&bare, Some("MIT OR Unlicense")),
            krate(&missing, Some("MIT")),
        ];
        let problems = render(&crates, &allow()).unwrap_err();
        assert_eq!(problems.len(), 7, "{problems:?}");
        assert!(problems[0].contains("no SPDX license expression"));
        assert!(problems[1].contains("no SPDX license expression"));
        assert!(problems[2].contains("not satisfied"));
        assert!(problems[3].contains("no standard text for GPL-3.0"));
        assert!(problems[4].contains("cannot parse"));
        assert!(problems[5].contains("no standard text for Unlicense"));
        assert!(problems[6].contains("cannot read"));
        let _ = fs::remove_dir_all(bare);
    }
}
