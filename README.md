# Double Claude

Due account Claude sullo stesso Mac, senza che si mescolino.

Chi usa Claude con un account di lavoro e uno personale scopre presto che i due si sovrappongono: le chat finiscono nel profilo sbagliato, un server MCP personale compare al lavoro, la scheda Code dell'app personale legge la configurazione di lavoro. `double-claude` separa i due profili su quattro livelli e controlla che restino separati.

| Livello | Cosa si mescola | Come si separa |
|---|---|---|
| Account | il login va all'app sbagliata | login dal browser, uno alla volta |
| App Desktop | una sola app, un solo account | seconda copia dell'app con `--user-data-dir` |
| Claude Code | chat, MCP, impostazioni in `~/.claude` | `CLAUDE_CONFIG_DIR`, anche nella scheda Code dell'app |
| Cartelle | ognuno legge i file dell'altro | divieti `Read`/`Edit` e, se vuoi, zone nel Terminale |

## Installazione

Nel Terminale:

```sh
curl -fsSL https://raw.githubusercontent.com/francescocolombo/double-claude/main/double-claude -o /tmp/double-claude && zsh /tmp/double-claude install
```

Il comando scarica un solo file, [`double-claude`](double-claude), lo controlla e lo copia in `~/.local/bin`. Poi:

```sh
double-claude init      # qualche domanda, salva la configurazione
double-claude doctor    # controlla cosa è separato e cosa no, senza modificare niente
```

Per disinstallarlo basta cancellare `~/.local/bin/double-claude` e la cartella `~/.config/double-claude`.

Requisiti: macOS, zsh (predefinita), Claude Code installato. Non servono altri programmi: la parte che legge e scrive i JSON gira con JavaScript for Automation, già presente in macOS.

## Comandi

| Comando | Cosa fa |
|---|---|
| `init` | configura i due profili con qualche domanda (le zone sono facoltative) |
| `doctor` | controlla cosa è già separato e cosa no, senza modificare niente |
| `plan` | mostra cosa farebbe `apply` |
| `apply [pezzi]` | separa tutto, oppure solo `shell`, `move`, `mcp`, `deny`, `app` |
| `open NOME` | apre l'app del profilo giusto (lo usano i launcher) |
| `status` | mostra le app Claude aperte e il loro profilo |
| `backup` / `restore` | salva una copia e torna indietro |

`apply` fa sempre un backup prima di cambiare qualcosa, in `~/.config/double-claude/backups`.

## Zone (facoltative)

Una zona lega un profilo ad alcune cartelle: per esempio `claude` solo in `~/Documents/work` e `claude-personal` ovunque tranne lì. `init` la propone, ma si può saltare: senza zone i due comandi funzionano in ogni cartella e i divieti proteggono comunque le configurazioni dell'altro profilo.

Le zone servono anche a capire di chi sono le chat già mescolate. Senza una zona, `apply move` non sposta niente. Si può aggiungere una zona più avanti rilanciando `init`.

## La seconda app

- La copia dell'app non si aggiorna da sola: un aggiornamento la riavvierebbe sull'account sbagliato. `apply app` scrive una policy locale nella cartella `<dati>-3p`, ma solo se la cartella non esiste: se c'è già (per esempio per un gateway di inferenza), non la tocca e `doctor` lo segnala.
- Al clic sul launcher, la copia si rifà solo se è più vecchia di Claude.app. Se è più recente o la versione non si legge, resta. La copia nuova nasce accanto e prende il posto della vecchia solo quando è completa.
- Il launcher aspetta che il lavoro sia finito: da macOS 27 i processi avviati da un'app che si chiude vengono interrotti.
- Ogni launcher ha un identificativo suo e l'icona di Claude. `init` chiede se tenerli fuori dal Dock (si aprono da Spotlight) oppure no (si possono fissare nel Dock).
- Se la copia è già aperta senza il suo profilo, il launcher chiede se chiuderla e riaprirla nel modo giusto. `doctor` controlla anche la copia fissata nel Dock e lo stesso account nelle due app.

## Da dove parti

- **Un solo account, ne aggiungi un secondo.** `init` → `apply`. Lo spostamento delle chat è facoltativo.
- **Due account, un solo Claude.** `init` → `plan` → `apply`. Con una zona, le chat e la cronologia del secondo account passano nel suo profilo; senza, restano dove sono.
- **Due profili che si mescolano.** `init` → `doctor`, poi solo i pezzi indicati con ✗.

## Caso d'uso

Un designer usa Claude con l'account aziendale per i progetti in `~/Documents/work` e con quello personale per tutto il resto. Ha già due app, ma:

- la scheda Code dell'app personale salva le chat nel profilo di lavoro;
- un server MCP personale compare anche nelle sessioni di lavoro;
- la cronologia del Terminale contiene i progetti di entrambi.

Con `init` sceglie "work" e "personal" e indica `~/Documents/work` come zona di work. `doctor` mostra quattro ✗. `apply` sposta le chat e la cronologia personali, sposta il server MCP, scrive i divieti e rifà il launcher dell'app personale con `CLAUDE_CONFIG_DIR`. Un secondo `doctor` dà tutti ✓.

Risultato:

```
claude          funziona solo dentro ~/Documents/work, account aziendale
claude-personal funziona ovunque tranne lì, account personale, config ~/.claude-personal
Claude          app di lavoro
Claude Personal seconda app, dati e scheda Code propri
```

## Trappole note

- Il login passa dal browser: prima esci da claude.ai e tieni chiusa l'altra app.
- `CLAUDE_CONFIG_DIR` vale solo all'avvio: dopo un cambio chiudi l'app con ⌘Q.
- Le due app hanno lo stesso identificativo: apri sempre dai launcher, non dalla copia fissata nel Dock.
- I divieti fermano gli strumenti file di Claude Code, non i comandi Bash.
- Restano in comune il programma `claude`, la chiave nel Portachiavi, log e cache dell'app. Per un muro totale serve un secondo utente macOS.

## Test

```sh
zsh tests/run.sh                  # motore JSON con node, gira anche su Linux
DC_TEST_JXA=1 zsh tests/run.sh    # su macOS: motore con osascript, come nell'uso reale
```

I test usano una home finta. Gli strumenti di macOS (`osacompile`, `open`, `ps`, `codesign`, il Dock) sono simulati; `plutil` è quello vero, quindi lo scenario dell'app gira solo su macOS. Sul proprio Mac il primo controllo sicuro è `double-claude doctor`, che non modifica niente.
