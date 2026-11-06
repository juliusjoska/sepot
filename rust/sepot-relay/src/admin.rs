//! Podpříkazy provozovatele: blokace identit, zajištění údajů a přehledy
//! (`sepot-relay <podpříkaz>` v kontejneru relaye, DB podle `DATABASE_URL`).
//!
//! Otisk, odkaz nebo klíč berou jen ze stdin: v argumentech procesu by je
//! viděl audit uzlu i historie shellu. Bez `--ano` nic nemění. Výstup jde
//! jen na stdout, česky.

use std::io::{Read, Write};

use chrono::NaiveDate;
use futures_util::TryStreamExt;
use serde_json::Value;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgConnection, PgPool};

use crate::blocking::{
    self, BlockError, BlockOptions, BlockReport, HoldState, Outcome, RegistrationInfo,
};
use crate::cleanup::{self, INACTIVE_REGISTRATION_DAYS};
use crate::fingerprint::{parse_admin_input, AdminInput, Fingerprint};
use crate::limits::InvalidSwitch;

/// Hotovo, včetně běhu nanečisto.
const EXIT_OK: i32 = 0;
/// Chyba databáze nebo chybějící schéma.
const EXIT_DB: i32 = 1;
/// Neplatný vstup nebo použití.
const EXIT_USAGE: i32 = 2;
/// Nic nenalezeno nebo není co měnit.
const EXIT_NOTHING: i32 = 3;

/// Strop stdin: pozvánka s odkazem má stovky bajtů.
const MAX_INPUT_BYTES: u64 = 64 * 1024;
/// Podpříkaz běží vedle relaye nad jeho DB; víc spojení nepotřebuje.
const DB_CONNECTIONS: u32 = 2;

const SHORT_NOT_ENOUGH: &str = "Zkratka SEP nestačí. Spusť `najit` a použij plný otisk.";
const NO_INPUT: &str =
    "Na stdin nic nepřišlo. Pošli plný otisk, odkaz s pozvánkou nebo identity klíč.";
const BAD_INPUT: &str =
    "Vstup není plný otisk, odkaz s pozvánkou, identity klíč (33 B, base64) ani zkratka SEP.";
const POSITIONAL: &str = "Otisk, odkaz ani klíč nepatří do argumentů (vidí je audit i historie \
     shellu). Pošli je na stdin.";
const SCHEMA_MISSING: &str = "Databáze nemá schéma 0005, nic nedělám.";
/// Přepínače, které berou hodnotu (`--do 2027-01-31` i `--do=2027-01-31`).
const VALUE_FLAGS: [&str; 2] = ["--do", "--dni"];

fn help() -> String {
    format!(
        "Použití: printf '%s\\n' \"$OTISK\" | sepot-relay <podpříkaz> [přepínače]

Otisk, odkaz s pozvánkou nebo identity klíč čte podpříkaz jen ze stdin.
Bez --ano nic nemění, jen vypíše, co by udělal.

  zablokovat [--zajistit] [--do RRRR-MM-DD] [--ano]
                              smaže registraci a zablokuje identitu
                              (výchozí konec dnes + {block} dní)
  odblokovat [--ano]          zruší blokaci, zajištění nechá
  zajistit [--dni N] [--ano]  kopie registrace na N dní (1–{hold}, výchozí {hold}),
                              nic nemaže
  uvolnit [--ano]             smaže zajištěnou kopii před lhůtou
  najit                       stav identity; bere i zkratku SEP
  vydat [--push]              registrace jako JSON, push tokeny jen s --push
  seznam                      platné blokace a zajištění (zkratky SEP)
  stav                        jen počty
  uklid --nanecisto           co by smazal úklid neaktivních registrací

Kódy: {EXIT_OK} hotovo (i nanečisto), {EXIT_DB} chyba databáze, {EXIT_USAGE} neplatný vstup,
{EXIT_NOTHING} nic nenalezeno nebo není co měnit.",
        block = blocking::BLOCK_DEFAULT_DAYS,
        hold = blocking::HOLD_MAX_DAYS,
    )
}

/// Co podpříkaz vypíše a s jakým kódem skončí.
#[derive(Debug)]
struct Reply {
    code: i32,
    text: String,
}

impl Reply {
    fn text(code: i32, text: impl Into<String>) -> Self {
        let mut text = text.into();
        if !text.ends_with('\n') {
            text.push('\n');
        }
        Self { code, text }
    }

    fn lines(code: i32, lines: Vec<String>) -> Self {
        Self::text(code, lines.join("\n"))
    }

    fn usage(text: impl Into<String>) -> Self {
        Self::text(EXIT_USAGE, text)
    }
}

fn db_error(e: sqlx::Error) -> Reply {
    Reply::text(EXIT_DB, format!("Chyba databáze: {e}"))
}

/// Podpříkaz nad jednou identitou: potřebuje plný otisk.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum IdentityCommand {
    Block {
        hold: bool,
        until: Option<NaiveDate>,
        apply: bool,
    },
    Unblock {
        apply: bool,
    },
    Hold {
        days: i32,
        apply: bool,
    },
    Release {
        apply: bool,
    },
    Export {
        push: bool,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Command {
    Identity(IdentityCommand),
    Find,
    List,
    Status,
    CleanupDryRun,
    Help,
}

impl Command {
    fn needs_input(self) -> bool {
        matches!(self, Self::Identity(_) | Self::Find)
    }
}

/// Přepínače za podpříkazem v pořadí, v jakém přišly.
struct Flags(Vec<(String, Option<String>)>);

impl Flags {
    fn parse(args: &[String]) -> Result<Self, Reply> {
        let mut flags = Vec::new();
        let mut args = args.iter();
        while let Some(arg) = args.next() {
            if !arg.starts_with('-') {
                return Err(Reply::usage(POSITIONAL));
            }
            let (name, inline) = match arg.split_once('=') {
                Some((name, value)) => (name, Some(value.to_string())),
                None => (arg.as_str(), None),
            };
            let value = match inline {
                Some(value) => Some(value),
                None if VALUE_FLAGS.contains(&name) => Some(
                    args.next()
                        .ok_or_else(|| Reply::usage(format!("Přepínač {name} potřebuje hodnotu.")))?
                        .clone(),
                ),
                None => None,
            };
            flags.push((name.to_string(), value));
        }
        Ok(Self(flags))
    }

    fn take(&mut self, name: &str) -> Option<Option<String>> {
        let index = self.0.iter().position(|(flag, _)| flag == name)?;
        Some(self.0.remove(index).1)
    }

    fn switch(&mut self, name: &str) -> Result<bool, Reply> {
        match self.take(name) {
            None => Ok(false),
            Some(None) => Ok(true),
            Some(Some(_)) => Err(Reply::usage(format!("Přepínač {name} nebere hodnotu."))),
        }
    }

    fn value(&mut self, name: &str) -> Option<String> {
        self.take(name).flatten()
    }

    /// Co zbylo, sem nepatří (neznámý, zdvojený nebo cizí přepínač).
    fn finish(self) -> Result<(), Reply> {
        match self.0.first() {
            None => Ok(()),
            Some((name, _)) => Err(Reply::usage(format!(
                "Přepínač {name} sem nepatří. Nápověda: sepot-relay napoveda"
            ))),
        }
    }
}

fn parse_until(text: &str) -> Result<NaiveDate, Reply> {
    NaiveDate::parse_from_str(text, "%Y-%m-%d")
        .map_err(|_| Reply::usage("Datum --do má tvar RRRR-MM-DD."))
}

fn parse_days(text: &str) -> Result<i32, Reply> {
    text.parse()
        .ok()
        .filter(|days| (1..=blocking::HOLD_MAX_DAYS).contains(days))
        .ok_or_else(|| {
            Reply::usage(format!(
                "--dni je celé číslo od 1 do {}.",
                blocking::HOLD_MAX_DAYS
            ))
        })
}

fn parse_command(args: &[String]) -> Result<Command, Reply> {
    let Some((name, rest)) = args.split_first() else {
        return Err(Reply::usage(help()));
    };
    let known = [
        "zablokovat",
        "odblokovat",
        "zajistit",
        "uvolnit",
        "najit",
        "vydat",
        "seznam",
        "stav",
        "uklid",
    ];
    if matches!(name.as_str(), "napoveda" | "help" | "--help" | "-h") {
        return Ok(Command::Help);
    }
    if !known.contains(&name.as_str()) {
        return Err(Reply::usage(help()));
    }
    let mut flags = Flags::parse(rest)?;
    let command = match name.as_str() {
        "zablokovat" => Command::Identity(IdentityCommand::Block {
            hold: flags.switch("--zajistit")?,
            until: flags
                .value("--do")
                .as_deref()
                .map(parse_until)
                .transpose()?,
            apply: flags.switch("--ano")?,
        }),
        "odblokovat" => Command::Identity(IdentityCommand::Unblock {
            apply: flags.switch("--ano")?,
        }),
        "zajistit" => Command::Identity(IdentityCommand::Hold {
            days: flags
                .value("--dni")
                .as_deref()
                .map(parse_days)
                .transpose()?
                .unwrap_or(blocking::HOLD_MAX_DAYS),
            apply: flags.switch("--ano")?,
        }),
        "uvolnit" => Command::Identity(IdentityCommand::Release {
            apply: flags.switch("--ano")?,
        }),
        "vydat" => Command::Identity(IdentityCommand::Export {
            push: flags.switch("--push")?,
        }),
        "najit" => Command::Find,
        "seznam" => Command::List,
        "stav" => Command::Status,
        _ => {
            if !flags.switch("--nanecisto")? {
                return Err(Reply::usage(
                    "Úklid běží jen v relayi (SEPOT_INACTIVE_CLEANUP=1). \
                     Ručně jde jen `uklid --nanecisto`.",
                ));
            }
            Command::CleanupDryRun
        }
    };
    flags.finish()?;
    Ok(command)
}

/// Identita ze stdin. Zkratku SEP bere jen `najit`: má 50 bitů a kolizní
/// klíč k cizí zkratce jde předpočítat, blokace podle ní by mohla zasáhnout
/// oběť.
fn target(command: Command, input: &str) -> Result<AdminInput, Reply> {
    match parse_admin_input(input) {
        Some(AdminInput::Short(_)) if command != Command::Find => {
            Err(Reply::usage(SHORT_NOT_ENOUGH))
        }
        Some(parsed) => Ok(parsed),
        None if input.trim().is_empty() => Err(Reply::usage(NO_INPUT)),
        None => Err(Reply::usage(BAD_INPUT)),
    }
}

fn read_input() -> Result<String, Reply> {
    let mut input = String::new();
    std::io::stdin()
        .take(MAX_INPUT_BYTES + 1)
        .read_to_string(&mut input)
        .map_err(|_| Reply::usage("Stdin se nedá přečíst jako text UTF-8."))?;
    if input.len() as u64 > MAX_INPUT_BYTES {
        return Err(Reply::usage("Vstup na stdin je příliš dlouhý."));
    }
    Ok(input)
}

/// Vstupní bod z `main`: vrací návratový kód procesu.
pub async fn run() -> i32 {
    let reply = run_command().await;
    // Výsledek nese návratový kód; zavřený stdout ho nemá přebít. `print!`
    // by na zavřené rouře zpanikařil (kód 101) až po provedené změně.
    let mut stdout = std::io::stdout().lock();
    let _ = stdout.write_all(reply.text.as_bytes());
    let _ = stdout.flush();
    reply.code
}

async fn run_command() -> Reply {
    let args: Vec<String> = match std::env::args_os()
        .skip(1)
        .map(|arg| arg.into_string())
        .collect()
    {
        Ok(args) => args,
        Err(_) => return Reply::usage("Argumenty nejsou platné UTF-8."),
    };
    let command = match parse_command(&args) {
        Ok(command) => command,
        Err(reply) => return reply,
    };
    if command == Command::Help {
        return Reply::text(EXIT_OK, help());
    }
    let input = if command.needs_input() {
        match read_input().and_then(|text| target(command, &text)) {
            Ok(input) => Some(input),
            Err(reply) => return reply,
        }
    } else {
        None
    };
    let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| crate::DEFAULT_DATABASE_URL.into());
    let pool = match PgPoolOptions::new()
        .max_connections(DB_CONNECTIONS)
        .connect(&url)
        .await
    {
        Ok(pool) => pool,
        Err(e) => return db_error(e),
    };
    let reply = execute(
        &pool,
        command,
        input,
        crate::limits::inactive_cleanup_from_env(),
    )
    .await;
    pool.close().await;
    reply
}

async fn has_schema(pool: &PgPool) -> sqlx::Result<bool> {
    sqlx::query_scalar(
        "SELECT to_regclass('blocked_identities') IS NOT NULL
            AND to_regclass('retired_addresses') IS NOT NULL
            AND to_regclass('identity_holds') IS NOT NULL",
    )
    .fetch_one(pool)
    .await
}

async fn execute(
    pool: &PgPool,
    command: Command,
    input: Option<AdminInput>,
    cleanup_switch: Result<bool, InvalidSwitch>,
) -> Reply {
    // Starší schéma (návrat na starý image a zpět bez migrace) nesmí
    // vypadat jako „identita nenalezena“.
    match has_schema(pool).await {
        Ok(true) => {}
        Ok(false) => return Reply::text(EXIT_DB, SCHEMA_MISSING),
        Err(e) => return db_error(e),
    }
    let result = match (command, input) {
        (Command::Identity(action), Some(AdminInput::Full(fingerprint))) => {
            identity(pool, action, &fingerprint).await
        }
        (Command::Identity(_), Some(AdminInput::Short(_))) => Ok(Reply::usage(SHORT_NOT_ENOUGH)),
        (Command::Find, Some(input)) => find(pool, input).await,
        (Command::Identity(_) | Command::Find, None) => Ok(Reply::usage(NO_INPUT)),
        (Command::List, _) => list(pool).await,
        (Command::Status, _) => status(pool, cleanup_switch).await,
        (Command::CleanupDryRun, _) => cleanup_dry_run(pool, cleanup_switch).await,
        (Command::Help, _) => Ok(Reply::text(EXIT_OK, help())),
    };
    result.unwrap_or_else(db_error)
}

async fn identity(
    pool: &PgPool,
    action: IdentityCommand,
    fingerprint: &Fingerprint,
) -> sqlx::Result<Reply> {
    match action {
        IdentityCommand::Block { hold, until, apply } => {
            let options = BlockOptions {
                until,
                hold,
                dry_run: !apply,
            };
            match blocking::block(pool, fingerprint, options).await {
                Ok(report) if apply => Ok(block_done(&report, hold)),
                Ok(report) => Ok(block_preview(fingerprint, &report, hold)),
                Err(BlockError::UntilOutOfRange { min, max }) => Ok(Reply::usage(format!(
                    "Konec blokace --do smí být od {min} do {max}."
                ))),
                Err(BlockError::Db(e)) => Err(e),
            }
        }
        IdentityCommand::Unblock { apply } => unblock(pool, fingerprint, apply).await,
        IdentityCommand::Hold { days, apply } => hold(pool, fingerprint, days, apply).await,
        IdentityCommand::Release { apply } => release(pool, fingerprint, apply).await,
        IdentityCommand::Export { push } => export(pool, fingerprint, push).await,
    }
}

/// Počet se správným českým tvarem: 1, 2–4, ostatní.
fn plural(n: u64, one: &str, few: &str, many: &str) -> String {
    let form = match n {
        1 => one,
        2..=4 => few,
        _ => many,
    };
    format!("{n} {form}")
}

fn last_seen(info: &RegistrationInfo) -> String {
    match info.last_seen_on {
        Some(day) => format!("poslední připojení {day}"),
        None => "zatím bez připojení".into(),
    }
}

fn identity_line(fingerprint: &Fingerprint, registration: Option<&RegistrationInfo>) -> String {
    let short = fingerprint.short();
    match registration {
        Some(info) => format!(
            "Identita {short}: registrovaná, {} zařízení, {}.",
            info.devices,
            last_seen(info)
        ),
        None => format!("Identita {short}: registrace nenalezena."),
    }
}

/// Kroky nanečisto: odrážky oddělené čárkou, poslední s tečkou.
fn preview(mut lines: Vec<String>, steps: Vec<String>) -> Vec<String> {
    lines.push("Nanečisto. S --ano:".into());
    let last = steps.len().saturating_sub(1);
    lines.extend(
        steps
            .into_iter()
            .enumerate()
            .map(|(i, step)| format!("  {step}{}", if i == last { "." } else { "," })),
    );
    lines.push("Nic nezměněno.".into());
    lines
}

fn hold_step(hold: &HoldState) -> String {
    match hold.outcome {
        Outcome::New => format!("zajistí kopii registrace do {}", hold.hold_until),
        Outcome::Extended => format!(
            "prodlouží zajištění kopie z {} do {}",
            hold.held_on, hold.hold_until
        ),
        Outcome::Unchanged => format!(
            "zajištění kopie z {} nechá, platí do {}",
            hold.held_on, hold.hold_until
        ),
    }
}

fn hold_done(hold: &HoldState) -> String {
    match hold.outcome {
        Outcome::New => format!("Zajištěno do {}.", hold.hold_until),
        Outcome::Extended => format!(
            "Zajištění kopie z {} prodlouženo do {}.",
            hold.held_on, hold.hold_until
        ),
        Outcome::Unchanged => format!(
            "Zajištění kopie z {} trvá do {}, nic se nezkracuje.",
            hold.held_on, hold.hold_until
        ),
    }
}

fn block_preview(fingerprint: &Fingerprint, report: &BlockReport, wanted_hold: bool) -> Reply {
    let removed = &report.removed;
    let mut steps = Vec::new();
    match &report.hold {
        Some(hold) => steps.push(hold_step(hold)),
        None if wanted_hold => steps.push(match report.earlier_hold_until {
            Some(until) => format!(
                "kopii nezajistí, registrace nenalezena; dřívější zajištění platí do {until} \
                 (prodloužení: `zajistit --dni N --ano`)"
            ),
            None => "kopii nezajistí, registrace nenalezena".into(),
        }),
        None => {}
    }
    if report.registration.is_some() {
        steps.push(format!(
            "smaže registraci, {} zařízení, {}, {}",
            removed.device_uuids.len(),
            plural(
                removed.push_tokens,
                "push token",
                "push tokeny",
                "push tokenů"
            ),
            plural(
                removed.envelopes,
                "nedoručenou obálku",
                "nedoručené obálky",
                "nedoručených obálek"
            ),
        ));
    }
    let retired = removed.retired.len() as u64;
    if retired > 0 {
        let held = if retired == 1 { "ji" } else { "je" };
        steps.push(format!(
            "vyřadí {} (drží {held} blokace)",
            plural(
                retired,
                "doručovací adresu",
                "doručovací adresy",
                "doručovacích adres"
            )
        ));
    }
    if report.older_addresses > 0 {
        steps.push(format!(
            "podrží {} této identity",
            plural(
                report.older_addresses as u64,
                "dříve vyřazenou adresu",
                "dříve vyřazené adresy",
                "dříve vyřazených adres"
            )
        ));
    }
    let until = report.blocked_until;
    let not_registered = if report.registration.is_none() {
        " (blokace zabrání nové registraci)"
    } else {
        ""
    };
    steps.push(match report.outcome {
        Outcome::New => format!("zablokuje identitu do {until}{not_registered}"),
        Outcome::Extended => format!("prodlouží blokaci do {until}"),
        Outcome::Unchanged => format!("blokaci nechá, platí do {until}"),
    });
    let lines = preview(
        vec![identity_line(fingerprint, report.registration.as_ref())],
        steps,
    );
    Reply::lines(block_code(report), lines)
}

/// Blokace beze změny, bez registrace a bez adres = není co měnit.
fn block_code(report: &BlockReport) -> i32 {
    let changes = report.outcome != Outcome::Unchanged
        || report.registration.is_some()
        || report.older_addresses > 0;
    if changes {
        EXIT_OK
    } else {
        EXIT_NOTHING
    }
}

fn block_done(report: &BlockReport, wanted_hold: bool) -> Reply {
    let removed = &report.removed;
    let until = report.blocked_until;
    let registered = report.registration.is_some();
    let mut first = match report.outcome {
        Outcome::New => format!("Zablokováno do {until} (nová blokace)."),
        Outcome::Extended => format!("Blokace už existovala, konec posunut na {until}."),
        Outcome::Unchanged => format!("Blokace už existovala do {until}, nic se nezkracuje."),
    };
    if !registered {
        first.push_str(match report.outcome {
            Outcome::New => " Registrace nenalezena, blokace zabrání nové registraci.",
            Outcome::Extended | Outcome::Unchanged => " Registrace nenalezena.",
        });
    }
    let mut lines = vec![first];
    if registered {
        let hold = report
            .hold
            .as_ref()
            .map(|hold| format!("{} ", hold_done(hold)))
            .unwrap_or_default();
        lines.push(format!(
            "{hold}Smazáno: {} zařízení, {}, {}. Vyřazeno adres: {}.",
            removed.device_uuids.len(),
            plural(
                removed.push_tokens,
                "push token",
                "push tokeny",
                "push tokenů"
            ),
            plural(removed.envelopes, "obálka", "obálky", "obálek"),
            removed.retired.len(),
        ));
    } else if wanted_hold {
        lines.push(match report.earlier_hold_until {
            Some(until) => format!(
                "Novou kopii nebylo z čeho zajistit. Dřívější zajištění platí do {until}, \
                 prodloužíš ho příkazem `zajistit --dni N --ano`."
            ),
            None => "Kopii nebylo z čeho zajistit.".into(),
        });
    }
    if report.older_addresses > 0 {
        lines.push(format!(
            "Dříve vyřazené adresy pod blokací: {}.",
            report.older_addresses
        ));
    }
    if registered {
        lines.push(format!(
            "Živá spojení relay odpojí do {} s.",
            crate::LIVE_CHECK_INTERVAL.as_secs()
        ));
    }
    let code = block_code(report);
    if code == EXIT_OK {
        let hold_end = if report.hold.is_some() {
            ", konec zajištění"
        } else {
            ""
        };
        lines.push(format!(
            "Do spisu zapiš: den blokace, konec blokace{hold_end}. Otisk patří jen do spisu."
        ));
    }
    Reply::lines(code, lines)
}

async fn unblock(pool: &PgPool, fingerprint: &Fingerprint, apply: bool) -> sqlx::Result<Reply> {
    let Some(report) = blocking::unblock(pool, fingerprint, !apply).await? else {
        return Ok(Reply::text(EXIT_NOTHING, "Blokace nenalezena."));
    };
    let hold = report
        .hold_until
        .map(|until| format!("Zajištění do {until} zůstává: může na něm viset příkaz orgánu."));
    let lines = if apply {
        let mut lines = vec![format!(
            "Odblokováno (blokace od {}, platila do {}).",
            report.blocked_on, report.expires_on
        )];
        if report.addresses > 0 {
            lines.push(format!(
                "Adresy držené blokací: {}; do {} je smí zaregistrovat jen tatáž identita.",
                report.addresses, report.addresses_until
            ));
        }
        lines.extend(hold);
        lines.push("Do spisu zapiš: den odblokování.".into());
        lines
    } else {
        let mut steps = vec!["zruší blokaci".to_string()];
        if report.addresses > 0 {
            steps.push(format!(
                "{} vyhradí do {} téže identitě",
                plural(
                    report.addresses,
                    "adresu drženou blokací",
                    "adresy držené blokací",
                    "adres držených blokací",
                ),
                report.addresses_until
            ));
        }
        let mut lines = preview(
            vec![format!(
                "Blokace od {} do {}.",
                report.blocked_on, report.expires_on
            )],
            steps,
        );
        lines.extend(hold);
        lines
    };
    Ok(Reply::lines(EXIT_OK, lines))
}

async fn hold(
    pool: &PgPool,
    fingerprint: &Fingerprint,
    days: i32,
    apply: bool,
) -> sqlx::Result<Reply> {
    let Some(report) = blocking::hold(pool, fingerprint, days, !apply).await? else {
        return Ok(Reply::text(
            EXIT_NOTHING,
            "Registrace ani zajištění nenalezeny, není co zajistit.",
        ));
    };
    let code = if report.hold.outcome == Outcome::Unchanged {
        EXIT_NOTHING
    } else {
        EXIT_OK
    };
    let lines = if apply {
        let mut lines = vec![hold_done(&report.hold)];
        if report.registration.is_some() {
            lines.push("Registrace zůstává beze změny.".into());
        }
        if code == EXIT_OK {
            lines.push(
                "Do spisu zapiš: den zajištění, konec zajištění. Otisk patří jen do spisu.".into(),
            );
        }
        lines
    } else {
        preview(
            vec![identity_line(fingerprint, report.registration.as_ref())],
            vec![hold_step(&report.hold)],
        )
    };
    Ok(Reply::lines(code, lines))
}

async fn release(pool: &PgPool, fingerprint: &Fingerprint, apply: bool) -> sqlx::Result<Reply> {
    let Some((held_on, hold_until)) = blocking::release(pool, fingerprint, !apply).await? else {
        return Ok(Reply::text(EXIT_NOTHING, "Zajištění nenalezeno."));
    };
    let lines = if apply {
        vec![
            format!("Zajištěná kopie z {held_on} (do {hold_until}) smazána."),
            "Do spisu zapiš: den uvolnění.".into(),
        ]
    } else {
        preview(
            vec![format!("Zajištění kopie z {held_on} do {hold_until}.")],
            vec!["smaže zajištěnou kopii".into()],
        )
    };
    Ok(Reply::lines(EXIT_OK, lines))
}

/// JSON ze snímku: `zdroj` říká, zda je ze zajištění, nebo z živých
/// tabulek. Push tokeny vydává jen na výslovný příkaz.
async fn export(pool: &PgPool, fingerprint: &Fingerprint, push: bool) -> sqlx::Result<Reply> {
    let Some((source, snapshot)) = blocking::export(pool, fingerprint).await? else {
        return Ok(Reply::text(
            EXIT_NOTHING,
            "Registrace ani zajištění nenalezeny.",
        ));
    };
    let decode = |e: serde_json::Error| sqlx::Error::Decode(Box::new(e));
    let mut value: Value = serde_json::from_str(&snapshot).map_err(decode)?;
    if let Some(object) = value.as_object_mut() {
        object.insert("zdroj".into(), source.as_str().into());
        if !push {
            let devices = object.get_mut("devices").and_then(Value::as_array_mut);
            for device in devices
                .into_iter()
                .flatten()
                .filter_map(Value::as_object_mut)
            {
                device.remove("push_token");
                device.remove("voip_token");
            }
        }
    }
    let json = serde_json::to_string_pretty(&value).map_err(decode)?;
    Ok(Reply::text(EXIT_OK, json))
}

struct IdentityStatus {
    registration: Option<RegistrationInfo>,
    /// (od, do)
    block: Option<(NaiveDate, NaiveDate)>,
    /// (kopie z, do)
    hold: Option<(NaiveDate, NaiveDate)>,
}

impl IdentityStatus {
    fn found(&self) -> bool {
        self.registration.is_some() || self.block.is_some() || self.hold.is_some()
    }

    fn lines(&self, fingerprint: &Fingerprint) -> Vec<String> {
        let registration = match &self.registration {
            Some(info) => format!(
                "ano, od {}, zařízení {}, {}",
                info.registered_on,
                info.devices,
                last_seen(info)
            ),
            None => "ne".into(),
        };
        let block = match self.block {
            Some((from, until)) => format!("do {until} (od {from})"),
            None => "ne".into(),
        };
        let hold = match self.hold {
            Some((held_on, until)) => format!("do {until} (kopie z {held_on})"),
            None => "ne".into(),
        };
        vec![
            format!(
                "Otisk {} ({})",
                fingerprint.to_crockford(),
                fingerprint.short()
            ),
            format!("  registrace: {registration}"),
            format!("  blokace: {block} · zajištění: {hold}"),
        ]
    }
}

async fn identity_status(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
) -> sqlx::Result<IdentityStatus> {
    let registration = match blocking::find_registration(conn, fingerprint).await? {
        Some(registration) => blocking::registration_info(conn, &registration.account_id).await?,
        None => None,
    };
    let block = sqlx::query_as(
        "SELECT blocked_on, expires_on FROM blocked_identities
          WHERE fingerprint = $1 AND expires_on >= current_date",
    )
    .bind(fingerprint.0)
    .fetch_optional(&mut *conn)
    .await?;
    let hold = sqlx::query_as(
        "SELECT held_on, hold_until FROM identity_holds
          WHERE fingerprint = $1 AND hold_until >= current_date",
    )
    .bind(fingerprint.0)
    .fetch_optional(&mut *conn)
    .await?;
    Ok(IdentityStatus {
        registration,
        block,
        hold,
    })
}

/// Otisky se zkratkou `short`: registrované identity (otisk počítá Rust,
/// Postgres BLAKE2b neumí), platné blokace a platná zajištění.
async fn matching_short(conn: &mut PgConnection, short: &str) -> sqlx::Result<Vec<Fingerprint>> {
    let mut found: Vec<Fingerprint> = Vec::new();
    {
        let mut keys = sqlx::query_scalar::<_, Vec<u8>>("SELECT identity_key FROM identities")
            .fetch(&mut *conn);
        while let Some(key) = keys.try_next().await? {
            let fingerprint = Fingerprint::of_identity_key(&key);
            if fingerprint.short() == short {
                found.push(fingerprint);
            }
        }
    }
    let listed: Vec<[u8; 32]> = sqlx::query_scalar(
        "SELECT fingerprint FROM blocked_identities WHERE expires_on >= current_date
         UNION
         SELECT fingerprint FROM identity_holds WHERE hold_until >= current_date",
    )
    .fetch_all(&mut *conn)
    .await?;
    for fingerprint in listed.into_iter().map(Fingerprint) {
        if fingerprint.short() == short && !found.contains(&fingerprint) {
            found.push(fingerprint);
        }
    }
    Ok(found)
}

async fn find(pool: &PgPool, input: AdminInput) -> sqlx::Result<Reply> {
    let mut conn = pool.acquire().await?;
    let fingerprints = match &input {
        AdminInput::Full(fingerprint) => vec![*fingerprint],
        AdminInput::Short(short) => matching_short(&mut conn, short).await?,
    };
    if let (AdminInput::Short(short), true) = (&input, fingerprints.is_empty()) {
        return Ok(Reply::text(
            EXIT_NOTHING,
            format!("Zkratka {short}: nic nenalezeno."),
        ));
    }
    let mut lines = Vec::new();
    let mut found = false;
    for fingerprint in &fingerprints {
        let status = identity_status(&mut conn, fingerprint).await?;
        found |= status.found();
        lines.extend(status.lines(fingerprint));
    }
    if fingerprints.len() > 1 {
        lines.push("Víc shod: vyžádej plný otisk.".into());
    }
    Ok(Reply::lines(
        if found { EXIT_OK } else { EXIT_NOTHING },
        lines,
    ))
}

async fn list(pool: &PgPool) -> sqlx::Result<Reply> {
    let blocks: Vec<([u8; 32], NaiveDate, NaiveDate)> = sqlx::query_as(
        "SELECT fingerprint, blocked_on, expires_on FROM blocked_identities
          WHERE expires_on >= current_date ORDER BY expires_on, blocked_on",
    )
    .fetch_all(pool)
    .await?;
    let holds: Vec<([u8; 32], NaiveDate, NaiveDate)> = sqlx::query_as(
        "SELECT fingerprint, held_on, hold_until FROM identity_holds
          WHERE hold_until >= current_date ORDER BY hold_until, held_on",
    )
    .fetch_all(pool)
    .await?;
    let row = |(fingerprint, from, until): &([u8; 32], NaiveDate, NaiveDate)| {
        format!(
            "  {}  od {from}  do {until}",
            Fingerprint(*fingerprint).short()
        )
    };
    let mut lines = vec![format!("Blokace: {}", blocks.len())];
    lines.extend(blocks.iter().map(row));
    lines.push(format!("Zajištění: {}", holds.len()));
    lines.extend(holds.iter().map(row));
    lines.push("Plný otisk patří do spisu.".into());
    Ok(Reply::lines(EXIT_OK, lines))
}

fn cleanup_state(switch: Result<bool, InvalidSwitch>) -> &'static str {
    match switch {
        Ok(true) => "zapnutý",
        Ok(false) => "vypnutý",
        Err(InvalidSwitch) => "vypnutý (neplatná hodnota SEPOT_INACTIVE_CLEANUP)",
    }
}

async fn status(pool: &PgPool, cleanup_switch: Result<bool, InvalidSwitch>) -> sqlx::Result<Reply> {
    let (blocks, next_unblock): (i64, Option<NaiveDate>) = sqlx::query_as(
        "SELECT count(*), min(expires_on) FROM blocked_identities WHERE expires_on >= current_date",
    )
    .fetch_one(pool)
    .await?;
    let (holds, next_release): (i64, Option<NaiveDate>) = sqlx::query_as(
        "SELECT count(*), min(hold_until) FROM identity_holds WHERE hold_until >= current_date",
    )
    .fetch_one(pool)
    .await?;
    let (retired, held): (i64, i64) = sqlx::query_as(
        "SELECT count(*), count(*) FILTER (WHERE expires_on IS NULL) FROM retired_addresses
          WHERE expires_on IS NULL OR expires_on >= current_date",
    )
    .fetch_one(pool)
    .await?;
    // Živá spojení zná jen relay; počet je horní odhad.
    let sweep = cleanup::dry_run(pool, &[]).await?;
    let next = |count: i64, day: Option<NaiveDate>| match day {
        Some(day) => format!("{count} (nejbližší konec {day})"),
        None => count.to_string(),
    };
    Ok(Reply::lines(
        EXIT_OK,
        vec![
            format!("Blokace: {}", next(blocks, next_unblock)),
            format!("Zajištění: {}", next(holds, next_release)),
            format!("Vyřazené adresy: {retired} (z toho drží blokace: {held})"),
            format!(
                "Úklid neaktivních: {}; lhůta {INACTIVE_REGISTRATION_DAYS} dní; teď by smazal {}.",
                cleanup_state(cleanup_switch),
                plural(
                    sweep.registrations,
                    "registraci",
                    "registrace",
                    "registrací"
                )
            ),
        ],
    ))
}

async fn cleanup_dry_run(
    pool: &PgPool,
    cleanup_switch: Result<bool, InvalidSwitch>,
) -> sqlx::Result<Reply> {
    let sweep = cleanup::dry_run(pool, &[]).await?;
    let lines = vec![
        format!(
            "Úklid neaktivních registrací (lhůta {INACTIVE_REGISTRATION_DAYS} dní), nanečisto:"
        ),
        format!(
            "  smazal by {}, {} zařízení, {}, {}.",
            plural(
                sweep.registrations,
                "registraci",
                "registrace",
                "registrací"
            ),
            sweep.devices,
            plural(
                sweep.push_tokens,
                "push token",
                "push tokeny",
                "push tokenů"
            ),
            plural(
                sweep.envelopes,
                "nedoručenou obálku",
                "nedoručené obálky",
                "nedoručených obálek"
            ),
        ),
        "Živá spojení vidí jen relay, skutečný běh je ušetří.".into(),
        format!("Úklid v relayi je {}.", cleanup_state(cleanup_switch)),
        "Nic nezměněno.".into(),
    ];
    let code = if sweep.registrations > 0 {
        EXIT_OK
    } else {
        EXIT_NOTHING
    };
    Ok(Reply::lines(code, lines))
}

#[cfg(test)]
mod tests {
    use base64::prelude::*;

    use super::*;

    fn args(line: &str) -> Vec<String> {
        line.split_whitespace().map(String::from).collect()
    }

    #[test]
    fn vstup_odmitne_zkratku_u_blokace() {
        let block = parse_command(&args("zablokovat --zajistit --ano")).expect("platné použití");
        let find = parse_command(&args("najit")).expect("platné použití");
        let short = "SEP-2TFMWYYW4M";
        assert_eq!(target(block, short).expect_err("zkratka").code, EXIT_USAGE);
        assert_eq!(
            target(find, short).ok(),
            Some(AdminInput::Short(short.into()))
        );

        let mut key = vec![0x05];
        key.extend(0u8..32);
        assert!(matches!(
            target(block, &BASE64_STANDARD.encode(&key)),
            Ok(AdminInput::Full(_))
        ));
        let mut without_type = key.clone();
        without_type[0] = 0x06;
        let link_without_ik = format!(
            "sepot://add/{}",
            BASE64_URL_SAFE.encode(r#"{"v":2,"n":"Jana"}"#)
        );
        for bad in [
            link_without_ik,
            BASE64_STANDARD.encode(&key[1..]),
            BASE64_STANDARD.encode(&without_type),
            String::new(),
        ] {
            assert_eq!(
                target(block, &bad).expect_err(&bad).code,
                EXIT_USAGE,
                "{bad}"
            );
        }

        for line in [
            "",
            "zablokuj",
            "zablokovat 2TFMWYYW4MRZH3BR8QCWQZVVM20EPFEP40N91S6J9HXW1GGHATRG",
            "zablokovat --push",
            "zablokovat --ano --ano",
            "zablokovat --do 5.11.2026",
            "zablokovat --do",
            "zajistit --dni 91",
            "zajistit --dni 0",
            "vydat --push=ano",
            "uklid",
        ] {
            assert_eq!(
                parse_command(&args(line)).expect_err(line).code,
                EXIT_USAGE,
                "{line}"
            );
        }
        assert_eq!(
            parse_command(&args("zablokovat --do=2027-01-31")).ok(),
            Some(Command::Identity(IdentityCommand::Block {
                hold: false,
                until: NaiveDate::from_ymd_opt(2027, 1, 31),
                apply: false,
            }))
        );
        assert_eq!(
            parse_command(&args("zajistit")).ok(),
            Some(Command::Identity(IdentityCommand::Hold {
                days: blocking::HOLD_MAX_DAYS,
                apply: false,
            }))
        );
        assert_eq!(
            parse_command(&args("uklid --nanecisto")).ok(),
            Some(Command::CleanupDryRun)
        );
        assert_eq!(parse_command(&args("napoveda")).ok(), Some(Command::Help));
    }

    #[test]
    fn tvary_cisel() {
        let forms = |n| plural(n, "obálka", "obálky", "obálek");
        assert_eq!(forms(0), "0 obálek");
        assert_eq!(forms(1), "1 obálka");
        assert_eq!(forms(3), "3 obálky");
        assert_eq!(forms(5), "5 obálek");
        assert_eq!(forms(12), "12 obálek");
    }
}

#[cfg(test)]
mod db_tests {
    //! Podpříkazy nad reálným Postgresem (testkit).
    //! #[ignore] — spouštět s DB: `cargo test -p sepot-relay -- --ignored`.
    use super::*;
    use crate::testkit::{self, rand_bytes, Isolated, TestIdentity};

    fn full(identity: &TestIdentity) -> Option<AdminInput> {
        Some(AdminInput::Full(identity.fingerprint))
    }

    /// Každá tabulka schématu: počet řádků a otisk obsahu (zachytí i UPDATE).
    async fn table_contents(pool: &PgPool) -> Vec<(String, i64, Option<String>)> {
        let tables: Vec<String> = sqlx::query_scalar(
            "SELECT table_name::text FROM information_schema.tables
              WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'
              ORDER BY 1",
        )
        .fetch_all(pool)
        .await
        .unwrap();
        let mut contents = Vec::new();
        for table in tables {
            let (rows, digest): (i64, Option<String>) = sqlx::query_as(&format!(
                "SELECT count(*), md5(string_agg(t::text, ',' ORDER BY t::text)) FROM {table} t"
            ))
            .fetch_one(pool)
            .await
            .unwrap();
            contents.push((table, rows, digest));
        }
        contents
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn admin_bez_schematu_skonci_1() {
        let isolated = Isolated::before_blocking().await;
        let identity = TestIdentity::new();
        for command in [
            Command::Identity(IdentityCommand::Block {
                hold: true,
                until: None,
                apply: true,
            }),
            Command::Find,
            Command::Status,
        ] {
            let reply = execute(&isolated.pool, command, full(&identity), Ok(false)).await;
            assert_eq!(reply.code, EXIT_DB, "{command:?}");
            assert_eq!(reply.text.trim_end(), SCHEMA_MISSING);
        }
        let (version, table): (i64, Option<String>) = sqlx::query_as(
            "SELECT max(version), to_regclass('blocked_identities')::text FROM _sqlx_migrations",
        )
        .fetch_one(&isolated.pool)
        .await
        .unwrap();
        assert_eq!(version, 4, "schéma beze změny");
        assert_eq!(table, None);
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn vydat_push_jen_s_prepinacem() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        state
            .register_push(
                &registered.device_uuid,
                crate::push::PLATFORM_APNS,
                Some(b"apns-token"),
                Some(b"voip-token"),
            )
            .await
            .expect("push");
        let export = |push| {
            execute(
                &state.pool,
                Command::Identity(IdentityCommand::Export { push }),
                full(&identity),
                Ok(false),
            )
        };
        let parse = |reply: Reply| -> Value {
            assert_eq!(reply.code, EXIT_OK, "{}", reply.text);
            serde_json::from_str(&reply.text).expect("JSON")
        };

        let json = parse(export(false).await);
        assert_eq!(json["zdroj"], "zive");
        let device = &json["devices"][0];
        assert_eq!(device["device_uuid"], hex::encode(&registered.device_uuid));
        assert!(device.get("push_token").is_none(), "{device}");
        assert!(device.get("voip_token").is_none(), "{device}");

        let json = parse(export(true).await);
        assert_eq!(json["devices"][0]["push_token"], hex::encode(b"apns-token"));
        assert_eq!(json["devices"][0]["voip_token"], hex::encode(b"voip-token"));

        // Po blokaci se zajištěním vydává kopii; tokeny zase jen s --push.
        blocking::block(
            &state.pool,
            &identity.fingerprint,
            BlockOptions {
                hold: true,
                ..BlockOptions::default()
            },
        )
        .await
        .expect("blokace");
        let json = parse(export(false).await);
        assert_eq!(json["zdroj"], "zajisteni");
        assert!(json["devices"][0].get("push_token").is_none());
        let json = parse(export(true).await);
        assert_eq!(json["devices"][0]["push_token"], hex::encode(b"apns-token"));

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_nanecisto_nic_nezmeni() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let identity = TestIdentity::new();
        let (older, current) = (rand_bytes(32), rand_bytes(32));
        let first = testkit::register(&state, &identity, &older)
            .await
            .expect("registrace");
        state
            .delete_identity(&first.account_id)
            .await
            .expect("smazání účtu");
        let registered = testkit::register(&state, &identity, &current)
            .await
            .expect("nová registrace");
        state
            .register_push(
                &registered.device_uuid,
                crate::push::PLATFORM_FCM,
                Some(b"fcm-token"),
                None,
            )
            .await
            .expect("push");
        testkit::enqueue(pool, &current).await;
        testkit::enqueue(pool, &current).await;

        let before = table_contents(pool).await;
        let block = |apply| {
            Command::Identity(IdentityCommand::Block {
                hold: true,
                until: None,
                apply,
            })
        };
        let reply = execute(pool, block(false), full(&identity), Ok(false)).await;
        assert_eq!(reply.code, EXIT_OK, "{}", reply.text);
        assert!(
            reply.text.contains("zajistí kopii registrace do"),
            "{}",
            reply.text
        );
        assert!(reply.text.contains("2 nedoručené obálky"), "{}", reply.text);
        assert!(
            reply.text.contains("podrží 1 dříve vyřazenou adresu"),
            "{}",
            reply.text
        );
        assert!(reply.text.ends_with("Nic nezměněno.\n"), "{}", reply.text);
        let hold = Command::Identity(IdentityCommand::Hold {
            days: 30,
            apply: false,
        });
        assert_eq!(
            execute(pool, hold, full(&identity), Ok(false)).await.code,
            EXIT_OK
        );
        assert_eq!(table_contents(pool).await, before, "nanečisto nic nezmění");

        let reply = execute(pool, block(true), full(&identity), Ok(false)).await;
        assert_eq!(reply.code, EXIT_OK, "{}", reply.text);
        let after_block = table_contents(pool).await;
        assert_ne!(after_block, before);
        for dry_run in [
            IdentityCommand::Unblock { apply: false },
            IdentityCommand::Release { apply: false },
            IdentityCommand::Hold {
                days: 10,
                apply: false,
            },
        ] {
            execute(pool, Command::Identity(dry_run), full(&identity), Ok(false)).await;
            assert_eq!(table_contents(pool).await, after_block, "{dry_run:?}");
        }
        isolated.remove().await;
    }

    /// Registrace zmizela, zajištění z dřívějška zůstalo: `zablokovat
    /// --zajistit` ho nesmí zamlčet a má odkázat na prodloužení.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_se_zajistenim_bez_registrace_ukaze_drivejsi_zajisteni() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        let hold_until = blocking::hold(pool, &identity.fingerprint, 30, false)
            .await
            .unwrap()
            .expect("zajištění")
            .hold
            .hold_until;
        state
            .delete_identity(&registered.account_id)
            .await
            .expect("smazání účtu");

        let block = |apply| {
            Command::Identity(IdentityCommand::Block {
                hold: true,
                until: None,
                apply,
            })
        };
        for apply in [false, true] {
            let reply = execute(pool, block(apply), full(&identity), Ok(false)).await;
            assert_eq!(reply.code, EXIT_OK, "{}", reply.text);
            let text = reply.text.to_lowercase();
            assert!(
                text.contains(&format!("dřívější zajištění platí do {hold_until}")),
                "{}",
                reply.text
            );
            assert!(text.contains("zajistit --dni n --ano"), "{}", reply.text);
        }
        testkit::forget(pool, &identity, &[&address]).await;
    }

    /// Blokace bez adres: odblokování nevypisuje řádek o nula adresách.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn odblokovat_bez_adres_nepise_o_adresach() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        blocking::block(pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");

        for apply in [false, true] {
            let unblock = Command::Identity(IdentityCommand::Unblock { apply });
            let reply = execute(pool, unblock, full(&identity), Ok(false)).await;
            assert_eq!(reply.code, EXIT_OK, "{}", reply.text);
            assert!(!reply.text.contains("adres"), "{}", reply.text);
            assert!(!reply.text.contains("Adres"), "{}", reply.text);
        }
        testkit::forget(pool, &identity, &[]).await;
    }
}
