import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Stderr
import cli.Stdout

## Shared command, environment and reporting helpers for repository scripts.
Script := [].{

	## A command-line program that repository scripts run by name.
	Command := { base : Cmd, program : OsStr }.{

		## Print the command line, then run it with inherited output. A nonzero
		## exit is an error.
		run! : Command, List(OsStr) => Try({}, _)
		run! = |self, args| {
			Stdout.line!("+ ${Str.join_with([self.program].concat(args).map(OsStr.display), " ")}")?
			self.base.args(args).exec_cmd!()
		}

		## Build the underlying basic-cli command with the supplied arguments.
		cmd : Command, List(OsStr) -> Cmd
		cmd = |self, args| self.base.args(args)

		## The program name or path this command runs.
		program : Command -> OsStr
		program = |self| self.program
	}

	## Construct a script command from a program name or path.
	command : OsStr -> Command
	command = |program| Command.{ base: Cmd.new(program), program }

	## The pinned tooling compiler: `ROC_STABLE`, falling back to `roc-stable`.
	## It runs and tests the scripts, and never the package.
	roc_stable! : () => Try(Command, _)
	roc_stable! = || compiler!("ROC_STABLE", "roc-stable")

	## The floating package compiler: `ROC_NIGHTLY`, falling back to `roc`.
	## Every check, test, build and bundle of the package and examples uses it.
	roc_nightly! : () => Try(Command, _)
	roc_nightly! = || compiler!("ROC_NIGHTLY", "roc")

	## Read a UTF-8 environment variable, or `Err(NotSet)` when it is absent or empty.
	env_str! : OsStr => Try(Str, _)
	env_str! = |name|
		match Env.var_str!(name) {
			Ok("") => Err(NotSet)
			Ok(value) => Ok(value)
			Err(VarNotFound(_)) => Err(NotSet)
			Err(err) => Err(EnvironmentInputError(OsStr.display(name), err))
		}

	## Print a labelled progress line.
	info! : Str, Str => Try({}, _)
	info! = |label, message| Stdout.line!("${label} ${message}")

	## Print a section heading.
	section! : Str => Try({}, _)
	section! = |title| Stdout.line!("\n=== ${title} ===")

	## Print a script error and return `ScriptFailed`.
	fail! : Str => Try(_, _)
	fail! = |message| {
		Stderr.line!("error: ${message}")?
		Err(ScriptFailed)
	}
}

compiler! = |variable, fallback|
	match Env.var!(variable) {
		Ok(value) => Ok(Script.command(value))
		Err(VarNotFound(_)) => Ok(Script.command(fallback))
		Err(err) => Err(EnvironmentInputError(OsStr.display(variable), err))
	}
