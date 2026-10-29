# Project: Airport Tycoon 3D
- Engine: Godot 4.7.2 (GDScript)
- Location: G:\Godot\test
- Executable: G:\Godot\Godot_v4.7.2-stable_win64.exe
- Design Doc: Google Doc "GDD - Airport Tycoon 3D" (Read ONCE on first session prompt only)
- Build Checklist: Google Sheet "Build Checklist - Airport Tycoon 3D" (Reference only, do not edit)

## Workflow Rules
1. **First-Prompt Initialization:** On the very first prompt of a new session, read the GDD and Build Checklist from Google Drive to anchor context. On all subsequent prompts in the session, skip reading them and rely on local project files.
2. **Environment Check:** Ensure the Godot executable and project folders are accessible and running correctly, verifying that all required programs are active and functioning before executing tasks.
3. **Step-by-Step Execution:** Build only the specific step given in the current prompt.
4. **Verification & Testing:** Run the game to check for errors, tell the user what to test, and provide a git commit message.
5. **No Checklist Edits:** The user manages the checklist manually.