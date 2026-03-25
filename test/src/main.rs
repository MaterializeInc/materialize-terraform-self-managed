mod cli;
mod commands;
mod helpers;
mod types;

use clap::Parser;

use cli::{Args, SubCommand};
use commands::{list, phase_apply, phase_destroy, phase_init, phase_verify};
use helpers::test_run_dir;

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let result = match &args.command {
        SubCommand::Init { provider } => phase_init(provider).await.map(|dir| {
            println!(
                "Use --test-run {} for subsequent commands.",
                dir.file_name().unwrap().to_string_lossy()
            );
        }),
        SubCommand::Apply { test_run } => {
            let dir = test_run_dir(test_run);
            match dir {
                Ok(dir) => phase_apply(&dir).await,
                Err(e) => Err(e),
            }
        }
        SubCommand::Verify { test_run } => {
            let dir = test_run_dir(test_run);
            match dir {
                Ok(dir) => phase_verify(&dir).await,
                Err(e) => Err(e),
            }
        }
        SubCommand::List { latest } => list(*latest).await,
        SubCommand::Destroy { test_run, rm } => {
            let dir = test_run_dir(test_run);
            match dir {
                Ok(dir) => phase_destroy(&dir, *rm).await,
                Err(e) => Err(e),
            }
        }
        SubCommand::Run {
            provider,
            destroy_on_failure,
        } => {
            async {
                let dir = phase_init(provider).await?;
                let result = async {
                    phase_apply(&dir).await?;
                    phase_verify(&dir).await?;
                    Ok(())
                }
                .await;
                if result.is_ok() || *destroy_on_failure {
                    phase_destroy(&dir, true).await?;
                }
                result
            }
            .await
        }
    };
    if let Err(e) = result {
        eprintln!("\nError: {e:#}");
        std::process::exit(1);
    }
}
