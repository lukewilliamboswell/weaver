#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import src/Script

main! = |_args| {
	# Assemble the complete site in target/www-preview and preview it on
	# loopback. PORT chooses the port (default 8000), and NO_SERVE=1 stops after
	# assembling. The static file server is Python's, from the environment.
	output = "target/www-preview"
	Script.roc_stable!()?
		.cmd(["scripts/build_docs.roc"])
		.env_str("DOCS_OUTPUT", output)
		.env_str("ROC_DOCS_URL_ROOT", "/main")
		.exec_cmd!()?
	match Script.env_str!("NO_SERVE") {
		Ok(_) => Ok({})
		Err(NotSet) => {
			port = Script.env_str!("PORT") ?? "8000"
			Script.info!("SERVING", "${output} at http://127.0.0.1:${port}/ (Ctrl-C to stop)")?
			Cmd.new("python3")
				.args_str(["-m", "http.server", port, "--bind", "127.0.0.1", "--directory", output])
				.exec_cmd!()
		}
		Err(err) => Err(err)
	}
}
