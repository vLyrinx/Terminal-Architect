# Contributing to Terminal Architect

Thanks for wanting to help. Terminal Architect is an early prototype, so there's plenty to do and no wrong place to start. If enough people message me about this project I will create a Discord so we can all communicate easily.

## Getting set up

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (the standard version, not .NET).
2. Clone this repository.
3. Open the folder in Godot and press F5 to run the game.

## Ways to help

- **Play and report:** download the latest release and open an issue for anything that breaks, feels wrong or is confusing. Screenshots help a lot.
- **Pick an open issue:** issues labelled `good first issue` are a good place to start.
- **Suggest a feature:** check the roadmap in the GDD first, then open an issue describing what you'd like and why.

## Working on code

- Use GDScript and tabs for indentation, following the existing files.
- Keep each system in its own script under `scripts/`, and give scripts short comments that explain what they do.
- Keep the look clean and bright, and keep performance in mind: the target is a mid-size airport at 60 fps on a laptop with integrated graphics.
- Make one change per pull request, and say what you tested.

## Pull requests

1. Fork the repository and create a branch for your change.
2. Run the game and check for errors in the Output panel.
3. Open a pull request describing the change and how you tested it.

If you're not sure whether something fits, open an issue first and ask.
