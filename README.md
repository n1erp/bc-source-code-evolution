# 📦 bc-source-tracker

Microsoft Dynamics 365 Business Central AL source code.  
Using commits and version tags (v26, v27, etc.), you can easily compare changes between Business Central versions and simplify upgrades.

---

## 🎯 Why this project exists

Business Central on-premise installations provide compiled `.app` artifacts, which are not suitable for source tracking.

This repository focuses on:

✅ Tracking real AL source code  
✅ Understanding Microsoft changes between versions  
✅ Making upgrades faster and safer  
✅ Preserving custom business logic  

---
## 🕒 Versioning approach
Each Business Central version is tracked by a commit and tag:

Example:

```bash
git commit -m "v26 - Business Central source"
git tag v26

git commit -m "v27 - Business Central source"
git tag v27
````

This allows:
* Easy comparison between versions
* Clean history without duplicated folders

---

## 🔍 How to compare versions

On GitHub:

1. Go to the repository
2. Click **Tags** or **Commits**
3. Compare `v26` with `v27`

You’ll see exactly what changed in Microsoft code and your custom extensions.

## 📦 Extract and clean Business Central application artifacts

When working with Business Central on-premise application packages, the folder structure often contains nested `.zip` files inside `source` and `test` folders.

This repository includes a PowerShell script that:

- Recursively extracts all `.zip` files
- Creates folders with the same name as each zip
- Removes the original `.zip` files
- Leaves only:
  - Extracted AL source code
  - `.app` artifacts (optional for reference)

### ▶️ How to run
Run:
```powershell
.\clean-bc-zips.ps1
```
This keeps the repository clean and focused on source code only.