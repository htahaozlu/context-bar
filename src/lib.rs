use zed_extension_api::{self as zed, Result};

struct ZedContextPilot;

impl zed::Extension for ZedContextPilot {
    fn new() -> Self {
        Self
    }

    fn run_slash_command(
        &self,
        command: zed::SlashCommand,
        _args: Vec<String>,
        worktree: Option<&zed::Worktree>,
    ) -> Result<zed::SlashCommandOutput> {
        if command.name != "hello" {
            return Err(format!("unknown slash command: {}", command.name));
        }

        let text = match worktree {
            Some(worktree) => {
                let root = worktree.root_path();
                format!(
                    "Sana su an `{}` dizininden sesleniyorum. Bu proje icin briefing hazirlamaya hazirim.",
                    root
                )
            }
            None => "Bir worktree baglami olmadan cagrildim. `/hello` komutunu bir proje icinde tekrar dene."
                .to_string(),
        };

        Ok(zed::SlashCommandOutput {
            text,
            sections: vec![],
        })
    }
}

zed::register_extension!(ZedContextPilot);
