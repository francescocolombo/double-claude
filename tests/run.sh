#!/bin/zsh
# Test di double-claude su una home finta. Richiede zsh e node (il motore JSON gira con node al posto di osascript).
# Uso: zsh tests/run.sh          (motore con node)
#      DC_TEST_JXA=1 zsh tests/run.sh   (su macOS: motore con osascript, come nell'uso reale)
emulate -R zsh
setopt pipe_fail
ROOT=${0:A:h:h}
CS=$ROOT/double-claude
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
pass=0 fail=0
check() { if eval "$2"; then print "  ✓ $1"; (( pass++ )); else print "  ✗ $1"; (( fail++ )); fi }

# claude finto: gestisce mcp add-json / remove / list sul .claude.json giusto
mkdir -p $T/bin
cat > $T/bin/claude <<'EOF'
#!/usr/bin/env node
const fs=require('fs'),H=process.env.HOME,c=process.env.CLAUDE_CONFIG_DIR;const f=c?c+'/.claude.json':H+'/.claude.json';
let j={};try{j=JSON.parse(fs.readFileSync(f,'utf8'))}catch(e){}
const a=process.argv.slice(2);if(a[0]==='--version'){console.log((process.env.FAKE_CLAUDE_VERSION||'2.1.303')+' (Claude Code)');process.exit(0)}j.mcpServers=j.mcpServers||{};
if(a[0]==='mcp'&&a[1]==='add-json'){if(j.mcpServers[a[2]]){process.exit(1)}j.mcpServers[a[2]]=JSON.parse(a[3]);}
else if(a[0]==='mcp'&&a[1]==='remove'){if(!j.mcpServers[a[2]])process.exit(1);delete j.mcpServers[a[2]];}
else if(a[0]==='mcp'&&a[1]==='list'){console.log(Object.keys(j.mcpServers).join('\n'));process.exit(0)}
fs.mkdirSync(require('path').dirname(f),{recursive:true});fs.writeFileSync(f,JSON.stringify(j,null,2));
EOF
chmod +x $T/bin/claude
export PATH=$T/bin:$PATH DC_SKIP_RUNNING_CHECK=1 NO_COLOR=1
[[ -n ${DC_TEST_JXA:-} ]] && unset DC_JS_RUNTIME || export DC_JS_RUNTIME=node
unset CLAUDE_CONFIG_DIR       # mai la config vera di chi lancia i test
export DC_LANG=it              # i controlli qui sotto leggono i messaggi in italiano; l'inglese ha il suo scenario
export DC_APP=$T/nessuna-app   # i test non devono mai vedere la Claude.app vera del Mac

# ---------------------------------------------------------------- scenario 1: due account mescolati, cartella dedicata ad A
print "Scenario 1: due account mescolati"
export HOME=$T/alex; H=$HOME
mkdir -p $H/.claude/{projects,file-history} $H/Documents/{work/app,side}
mk() { local d=$H/.claude/projects/${1//[^A-Za-z0-9]/-}; mkdir -p $d
  print -r -- "{\"type\":\"user\",\"cwd\":\"$1\",\"sessionId\":\"$2\"}" > $d/$2.jsonl
  mkdir -p $H/.claude/file-history/$2; print x > $H/.claude/file-history/$2/f; }
mk $H/Documents/work s1; mk $H/Documents/work/app s2; mk $H s3; mk $H/Documents/side s4; mk $H/Documents/work-old s6
print -l "{\"display\":\"a\",\"project\":\"$H/Documents/work\"}" "{\"display\":\"b\",\"project\":\"$H\"}" "{\"display\":\"c\",\"project\":\"$H/Documents/side\"}" > $H/.claude/history.jsonl
cat > $H/.claude.json <<EOF
{"oauthAccount":{"emailAddress":"alex@acme.example"},"mcpServers":{"notes":{"type":"stdio","command":"npx","args":["notes-mcp"]},"github":{"type":"http","url":"https://x"}},
 "projects":{"$H/Documents/work":{},"$H/Documents/work/app":{},"$H":{},"$H/Documents/side":{"allowedTools":["Bash(npm test)"],"mcpServers":{"db":{"command":"db-mcp"}}}}}
EOF
print '{"permissions":{"allow":["Bash(ls:*)"]}}' > $H/.claude/settings.json
print -l 'export X=1' 'alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"' > $H/.zshrc
cd $H

printf '2\nwork\npersonal\n3\n~/Documents/work\nnotes\ns\ns\n' | $CS init >/dev/null
check "init salva la config" "[[ -f $H/.config/double-claude/config ]]"
check "cartella di A e moduli scelti" "grep -q 'DC_A_DIRS=($H/Documents/work)' $H/.config/double-claude/config && grep -q 'DC_B_DIRS=()' $H/.config/double-claude/config && grep -q 'DC_MODULES=(shell move mcp deny)' $H/.config/double-claude/config"
check "nome app con spazio salvato tra virgolette" "grep -q 'DC_B_APP=Claude\\\\ Personal' $H/.config/double-claude/config"
out=$($CS doctor)
check "doctor trova 3 chat di B in A (work-old riconosciuta dal cwd)" "[[ \$out == *'3 chat, 2 righe di cronologia, 2 voci di registro'* ]]"
check "doctor segnala l'alias" "[[ \$out == *'alias scavalca'* ]]"
$CS --yes apply >/dev/null
check "in A restano solo work e work/app" "[[ \$(ls $H/.claude/projects | wc -l) -eq 2 ]]"
check "B riceve 3 chat" "[[ \$(ls $H/.claude-personal/projects | wc -l) -eq 3 ]]"
check "file-history segue le chat" "[[ -d $H/.claude-personal/file-history/s3 && -d $H/.claude/file-history/s1 ]]"
check "cronologia divisa" "[[ \$(wc -l < $H/.claude-personal/history.jsonl) -eq 2 && \$(wc -l < $H/.claude/history.jsonl) -eq 1 ]]"
check "registro di A ripulito" "node -e \"process.exit(Object.keys(require('$H/.claude.json').projects).length===2?0:1)\""
check "MCP notes spostato in B" "node -e \"j=require('$H/.claude-personal/.claude.json');k=require('$H/.claude.json');process.exit(j.mcpServers.notes&&!k.mcpServers.notes?0:1)\""
check "divieti scritti e regole utente conservate" "grep -q 'Read(~/.claude-personal/\*\*)' $H/.claude/settings.json && grep -q 'Bash(ls:\*)' $H/.claude/settings.json"
check "divieti di B sulla cartella di lavoro" "grep -q 'Read(~/Documents/work/\*\*)' $H/.claude-personal/settings.json"
check "registro spostato in B con server MCP e permessi del progetto" "node -e \"b=require('$H/.claude-personal/.claude.json').projects['$H/Documents/side'];process.exit(b&&b.mcpServers.db&&b.allowedTools[0]==='Bash(npm test)'?0:1)\""
check "work legge solo dalla sua cartella" "node -e \"p=require('$H/.claude/settings.json').permissions;process.exit(p.blockReadsOutsideWorkingDirectories===true&&p.additionalDirectories[0]==='$H/Documents/work'?0:1)\""
check "personal senza cartella: nessun blocco" "! grep -q blockReads $H/.claude-personal/settings.json"
$CS --yes apply shell >/dev/null
check "blocco zshrc idempotente" "[[ \$(grep -c '>>> double-claude' $H/.zshrc) -eq 1 ]]"
sed -i.bak '/^alias/d' $H/.zshrc
r1=$(cd $H/Documents/work/app && zsh -c "source $H/.zshrc; claude-personal x" 2>&1)
check "B rifiutato nella cartella di A" "[[ \$r1 == *'questa cartella è di work'* ]]"
r2=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude x" 2>&1)
check "A rifiutato fuori dalla sua cartella" "[[ \$r2 == *'lavora solo in ~/Documents/work'* ]]"
r3=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude-personal mcp list" 2>&1)
check "B usa la sua config fuori dalla cartella di A" "[[ \$r3 == *notes* ]]"
out=$($CS doctor)
check "doctor dopo apply: resta solo il login di B" "[[ \$out == *'1 cosa da sistemare'* ]]"
check "doctor: work legge solo dalla sua cartella" "[[ \$out == *'work legge file solo da: ~/Documents/work'* ]]"
out=$(FAKE_CLAUDE_VERSION=2.1.200 $CS doctor)
check "doctor: Claude Code troppo vecchio per il blocco" "[[ \$out == *'Claude Code 2.1.200 non conosce il blocco delle letture'* ]]"

n=$(ls -d $H/.config/double-claude/backups/*.noindex | wc -l)
print "$n\ns" | $CS restore >/dev/null 2>&1   # il più vecchio
check "restore al primo backup rimette le chat in A" "[[ \$(ls $H/.claude/projects | wc -l) -eq 5 ]]"
check "restore toglie la config di B che non esisteva" "[[ ! -d $H/.claude-personal ]]"

# ---------------------------------------------------------------- scenario 2: un solo account, cartella dedicata a B, risposte da stdin
print "Scenario 2: un solo account, cartella dedicata a B"
export HOME=$T/sam; H=$HOME; mkdir -p $H/Projects; cd $H
print '{"oauthAccount":{"emailAddress":"sam@example.org"},"mcpServers":{}}' > $H/.claude.json
printf '1\npersonal\nacme\n2\n~/Projects/acme\nn\ns\n' | $CS init >/dev/null
check "start=one, cartella di B" "grep -q 'DC_START=one' $H/.config/double-claude/config && grep -q 'DC_B_DIRS=($H/Projects/acme)' $H/.config/double-claude/config"
check "move non scelto" "grep -q 'DC_MODULES=(shell deny)' $H/.config/double-claude/config"
plan=$($CS plan)
check "claude rifiutato dentro la cartella di B" "[[ \$plan == *'claude: questa cartella è di acme'* ]]"
check "plan: acme legge solo dalla sua cartella" "[[ \$plan == *'acme legge file solo da: ~/Projects/acme'* ]]"
check "plan annuncia la cartella da creare" "[[ \$plan == *'Crea anche le cartelle dedicate: ~/Projects/acme'* ]]"
out=$($CS --yes apply shell)
check "login di B dalla sua cartella" "[[ \$out == *'cd ~/Projects/acme && claude-acme'* ]]"
check "apply crea la cartella di B" "[[ -d $H/Projects/acme ]]"
for i in {1..7}; do $CS backup >/dev/null; done
check "si tengono solo gli ultimi 5 backup" "[[ \$(ls -d $H/.config/double-claude/backups/*.noindex | wc -l) -eq 5 ]]"

# ---------------------------------------------------------------- scenario 3: zone saltate
print "Scenario 3: zone saltate (--yes)"
export HOME=$T/lee; H=$HOME; mkdir -p $H/Documents/any; cd $H
SCR="$H/Library/Application Support/Claude-Personal/scratch-workspaces/x/y"
d=$H/.claude/projects/${SCR//[^A-Za-z0-9]/-}; mkdir -p $d; print -r -- "{\"cwd\":\"$SCR\"}" > $d/s.jsonl
mkdir -p $H/.claude/projects/-Users-lee-Documents-any; print -r -- "{\"cwd\":\"$H/Documents/any\"}" > $H/.claude/projects/-Users-lee-Documents-any/t.jsonl
print -r -- "{\"oauthAccount\":{\"emailAddress\":\"lee@example.org\"},\"projects\":{\"$SCR\":{}}}" > $H/.claude.json
$CS --yes init >/dev/null
check "--yes non sceglie cartelle dedicate" "grep -q 'DC_A_DIRS=()' $H/.config/double-claude/config && grep -q 'DC_B_DIRS=()' $H/.config/double-claude/config"
check "senza cartelle dedicate lo spostamento resta proposto (scheda Code)" "grep -q 'DC_MODULES=(shell move deny)' $H/.config/double-claude/config"
out=$($CS doctor)
check "doctor vede la chat della scheda Code di B finita in A" "[[ \$out == *'1 chat, 0 righe di cronologia, 1 voci di registro'* ]]"
out=$($CS doctor)
check "doctor spiega che non ci sono cartelle dedicate" "[[ \$out == *'Nessuna: claude e claude-personal funzionano in ogni cartella'* ]]"
$CS --yes apply >/dev/null
r1=$(cd $H/Documents/any && zsh -c "source $H/.zshrc; whence -w claude-personal; whence -w claude" 2>&1)
check "chat della scheda Code spostata in B, l'altra resta in A" "[[ -d $H/.claude-personal/projects/${${SCR//[^A-Za-z0-9]/-}} && -d $H/.claude/projects/-Users-lee-Documents-any ]]"
check "senza zone: solo la funzione di B, claude resta quello vero" "[[ \$r1 == *'claude-personal: function'* && \$r1 != *'claude: function'* ]]"

# ---------------------------------------------------------------- scenario 3b: una cartella per ciascuno
print "Scenario 3b: una cartella per ciascuno"
export HOME=$T/max; H=$HOME; mkdir -p $H/.claude/projects $H/Documents/side; cd $H
for p in $H/Documents/work/a $H/Documents/personal/b $H/Documents/side; do
  d=$H/.claude/projects/${p//[^A-Za-z0-9]/-}; mkdir -p $d; print -r -- "{\"cwd\":\"$p\"}" > $d/x.jsonl; done
print '{"oauthAccount":{"emailAddress":"max@example.org"}}' > $H/.claude.json
printf '2\nwork\npersonal\n4\n\n\ns\ns\n' | $CS init >/dev/null
check "due cartelle salvate" "grep -q 'DC_A_DIRS=($H/Documents/work)' $H/.config/double-claude/config && grep -q 'DC_B_DIRS=($H/Documents/personal)' $H/.config/double-claude/config"
out=$($CS doctor)
check "doctor: manca la cartella di personal, quella di work c'è dopo apply" "[[ \$out == *'manca la cartella ~/Documents/personal di personal'* ]]"
check "in A solo la chat dentro la cartella di B è di B" "[[ \$out == *'1 chat'* ]]"
$CS --yes apply >/dev/null
check "cartelle create, chat di personal spostata, side resta in A" "[[ -d $H/Documents/work && -d $H/Documents/personal && \$(ls $H/.claude-personal/projects) == *personal-b && \$(ls $H/.claude/projects | wc -l) -eq 2 ]]"
r1=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude x; claude-personal x" 2>&1)
check "fuori da entrambe: nessuno dei due parte" "[[ \$r1 == *'claude: lavora solo in ~/Documents/work.'* && \$r1 == *'claude-personal: lavora solo in ~/Documents/personal.'* ]]"
r2=$(cd $H/Documents/personal && zsh -c "source $H/.zshrc; claude x" 2>&1)
check "claude nella cartella di personal: indica claude-personal" "[[ \$r2 == *'questa cartella è di personal. Qui usa claude-personal'* ]]"
r3=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude mcp list" 2>&1)
check "comandi di gestione ovunque" "[[ \$r3 != *'lavora solo'* ]]"
check "divieti incrociati" "grep -q 'Read(~/Documents/personal/\*\*)' $H/.claude/settings.json && grep -q 'Read(~/Documents/work/\*\*)' $H/.claude-personal/settings.json"
check "una cartella per ciascuno: blocco in tutti e due i profili" "grep -q '\"blockReadsOutsideWorkingDirectories\": true' $H/.claude/settings.json && grep -q '\"blockReadsOutsideWorkingDirectories\": true' $H/.claude-personal/settings.json"
node -e "f='$H/.claude/settings.json';j=require(f);j.permissions.deny.push('Read(~/segreti/**)');j.sandbox={network:{allowedDomains:['example.org']}};require('fs').writeFileSync(f,JSON.stringify(j))"
sed -i.bak 's/^DC_SANDBOX=0/DC_SANDBOX=1/' $H/.config/double-claude/config
$CS --yes apply deny >/dev/null
check "sandbox attivo nei due profili" "node -e \"a=require('$H/.claude/settings.json');b=require('$H/.claude-personal/settings.json');process.exit(a.sandbox.enabled&&b.sandbox.enabled?0:1)\""
sed -i.bak 's/^DC_SANDBOX=1/DC_SANDBOX=0/; s/^DC_A_DIRS=.*/DC_A_DIRS=()/; s/^DC_B_DIRS=.*/DC_B_DIRS=()/' $H/.config/double-claude/config
$CS --yes apply deny >/dev/null
check "tolte le cartelle: via blocco, cartelle di lavoro e divieti incrociati" "node -e \"p=require('$H/.claude/settings.json').permissions;process.exit(!p.blockReadsOutsideWorkingDirectories&&!p.additionalDirectories&&!p.deny.some(x=>x.includes('Documents/personal'))?0:1)\""
check "regole e impostazioni dell'utente restano" "node -e \"j=require('$H/.claude/settings.json');process.exit(j.permissions.deny.includes('Read(~/segreti/**)')&&j.sandbox.network.allowedDomains[0]==='example.org'&&j.sandbox.enabled===undefined?0:1)\""
out=$($CS doctor)
check "doctor dopo il cambio: niente avanzi" "[[ \$out != *'configurazione precedente'* ]]"
print -l 'DC_A_LABEL=work' 'DC_B_LABEL=personal' 'DC_ZONE_OWNER=b' "DC_ZONE_DIRS=($H/Documents/personal)" 'DC_MODULES=(shell)' > $H/.config/double-claude/config
plan=$($CS plan)
check "config della 1.1.0 (zona di B) letta come cartella di B" "[[ \$plan == *'_dc_b=('* && \$plan == *'Documents/personal'* && \$plan == *'claude-personal: lavora solo in ~/Documents/personal. Qui usa claude.'* ]]"

# ---------------------------------------------------------------- scenario 4: app Desktop (strumenti macOS simulati)
print "Scenario 4: app Desktop"
if ! whence -p plutil >/dev/null; then print "  - saltato: serve plutil (macOS)"
else
export HOME=$T/kim; H=$HOME; mkdir -p $H; cd $H
M=$T/mac; mkdir -p $M
mkplist() { print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>$1</string><key>CFBundleShortVersionString</key><string>$2</string></dict></plist>" > $3; }
SRC=$T/apps/Claude.app; mkdir -p $SRC/Contents/{MacOS,Resources}; mkplist com.anthropic.claudefordesktop 2.9.1 $SRC/Contents/Info.plist
cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns $SRC/Contents/Resources/electron.icns; print bin > $SRC/Contents/MacOS/Claude
cat > $M/osacompile <<'EOF'
#!/bin/zsh
while (( $# )); do case $1 in -o) o=$2; shift 2;; -e) e=$2; shift 2;; *) shift;; esac; done
mkdir -p "$o/Contents/Resources/Scripts" "$o/Contents/MacOS"
print -r -- '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.apple.ScriptEditor.id.applet</string></dict></plist>' > "$o/Contents/Info.plist"
print -r -- "$e" > "$o/Contents/Resources/Scripts/main.scpt"; print x > "$o/Contents/Resources/applet.icns"; print x > "$o/Contents/Resources/Assets.car"
EOF
cat > $M/osascript <<'EOF'
#!/bin/zsh
if [[ "$*" == *'display dialog'* ]]; then print -r -- "${FAKE_DIALOG:-Riapri}"
elif [[ "$*" == *NSRunningApplication* ]]; then print -r -- "quit ${@[-1]}" >> $LOGS/quit.log
elif [[ $1 == -l ]]; then exec /usr/bin/osascript "$@"   # il motore JSON
else print -r -- "$*" >> $LOGS/osascript.log; fi
EOF
print -l '#!/bin/zsh' 'print -r -- "$*" >> $LOGS/open.log' > $M/open
print -l '#!/bin/zsh' 'cat $LOGS/ps.txt 2>/dev/null' > $M/ps
print -l '#!/bin/zsh' '[[ "$1 $2" == "read com.apple.dock" ]] && cat $LOGS/dock.txt 2>/dev/null' > $M/defaults
print -l '#!/bin/zsh' 'print -r -- "$*" >> $LOGS/lsregister.log' > $M/lsregister
print -l '#!/bin/zsh' 'cat "$1"' > $M/osadecompile
print -l '#!/bin/zsh' 'exit 0' > $M/codesign
chmod +x $M/*
export PATH=$M:$PATH DC_APP=$SRC DC_FAKE_MAC=1 DC_LSREGISTER=$M/lsregister LOGS=$T/logs; mkdir -p $LOGS
SELF_BIN=$CS

printf '1\nwork\npersonal\n1\ns\nn\ns\ns\n' | $CS init >/dev/null
check "init: app scelta, launcher fuori dal Dock" "grep -q 'DC_MODULES=(shell deny app)' $H/.config/double-claude/config && grep -q 'DC_LAUNCHER_HIDE=1' $H/.config/double-claude/config"
CL="$H/Library/Application Support/claude-personal-app.noindex/Claude Personal.app"
D="$H/Library/Application Support/Claude-Personal"; P3="$D-3p"
LB="$H/Applications/Claude Personal.app"; LA="$H/Applications/Claude.app"

mkdir -p "$P3"; print '{"gateway":1}' > "$P3/inference.json"
out=$($CS --yes apply app)
check "-3p di un altro strumento: non la tocca" "[[ \$out == *'non è di double-claude'* && ! -e '$P3/configLibrary' ]] && grep -q gateway '$P3/inference.json'"
out=$($CS doctor)
check "doctor: aggiornamenti attivi con -3p altrui" "[[ \$out == *'si aggiorna da sola'* && \$out == *'non la tocco'* ]]"
rm -rf "$P3"
out=$($CS --yes apply app)
check "copia creata" "[[ -f '$CL/Contents/Info.plist' && ! -e '$CL.refreshing' && ! -e '$CL.previous' ]]"
id=$(node -e "console.log(require('$P3/configLibrary/_meta.json').appliedId)" 2>/dev/null)
check "-3p: policy che blocca gli aggiornamenti" "[[ -n \$id ]] && grep -q '\"disableAutoUpdates\": true' '$P3/configLibrary/'\$id.json && [[ -f '$P3/.double-claude' ]]"
$CS --yes apply app >/dev/null
check "-3p: secondo apply riusa la stessa policy" "[[ \$(ls '$P3/configLibrary' | wc -l) -eq 2 ]]"
check "launcher: identificativo unico per profilo" "[[ \$(plutil -extract CFBundleIdentifier raw -o - '$LB/Contents/Info.plist') == local.double-claude.personal && \$(plutil -extract CFBundleIdentifier raw -o - '$LA/Contents/Info.plist') == local.double-claude.work ]]"
check "launcher: LSUIElement solo se scelto" "[[ \$(plutil -extract LSUIElement raw -o - '$LB/Contents/Info.plist') == true ]]"
check "launcher: icona di Claude, Assets.car tolto" "cmp -s '$SRC/Contents/Resources/electron.icns' '$LB/Contents/Resources/applet.icns' && [[ ! -e '$LB/Contents/Resources/Assets.car' ]]"
check "launcher: aspetta, senza &" "grep -q 'open b > /dev/null 2>&1\"' '$LB/Contents/Resources/Scripts/main.scpt' && ! grep -q '&\"' '$LB/Contents/Resources/Scripts/main.scpt'"
check "launcher registrati con lsregister -f" "grep -q 'Claude Personal.app' $LOGS/lsregister.log"
sed -i.bak 's/^DC_LAUNCHER_HIDE=1/DC_LAUNCHER_HIDE=0/' $H/.config/double-claude/config
$CS --yes apply app >/dev/null
check "launcher: senza LSUIElement si può fissare nel Dock" "! plutil -extract LSUIElement raw -o - '$LB/Contents/Info.plist' >/dev/null 2>&1"

plutil -replace CFBundleShortVersionString -string 2.10.0 "$CL/Contents/Info.plist"
$CS --yes apply app >/dev/null
check "copia più nuova (2.10.0 > 2.9.1): non torna indietro" "[[ \$(plutil -extract CFBundleShortVersionString raw -o - '$CL/Contents/Info.plist') == 2.10.0 ]]"
plutil -replace CFBundleShortVersionString -string 2.9.0 "$CL/Contents/Info.plist"
out=$($CS doctor)
check "doctor: copia più vecchia segnalata" "[[ \$out == *'più vecchia'* ]]"
$CS --yes apply app >/dev/null
check "copia più vecchia: rifatta" "[[ \$(plutil -extract CFBundleShortVersionString raw -o - '$CL/Contents/Info.plist') == 2.9.1 ]]"

mv "$CL" "$CL.previous"; mkdir -p "$CL.refreshing"
$CS open b
check "open: recupera una ricostruzione interrotta" "[[ -f '$CL/Contents/Info.plist' && ! -e '$CL.previous' && ! -e '$CL.refreshing' ]]"
check "open b: CLAUDE_CONFIG_DIR e --user-data-dir" "grep -qF -- '--env CLAUDE_CONFIG_DIR=$H/.claude-personal --args --user-data-dir=$D' $LOGS/open.log"

print -r -- "99999 $CL/Contents/MacOS/Claude" > $LOGS/ps.txt
: > $LOGS/open.log
FAKE_DIALOG='Lascia così' $CS open b
check "copia senza profilo, l'utente la lascia: niente chiusura" "[[ ! -s $LOGS/open.log && ! -e $LOGS/quit.log ]]"
$CS open b
check "copia senza profilo: chiusa e riaperta col profilo" "grep -q 'quit 99999' $LOGS/quit.log && grep -q -- '--user-data-dir=' $LOGS/open.log"
out=$($CS status)
check "status segnala la copia senza profilo" "[[ \$out == *'senza il suo profilo'* ]]"

mkdir -p "$D" "$H/Library/Application Support/Claude"
print '{"lastKnownAccountUuid":"u-1"}' | tee "$D/config.json" > "$H/Library/Application Support/Claude/config.json"
print -r -- '"_CFURLString" = "file:///Users/kim/Library/Application%20Support/claude-personal-app.noindex/Claude%20Personal.app/";' > $LOGS/dock.txt
out=$($CS doctor)
check "doctor: copia aperta senza profilo" "[[ \$out == *'aperta senza il suo profilo'* ]]"
check "doctor: copia fissata nel Dock" "[[ \$out == *'nel Dock è fissata la copia'* ]]"
check "doctor: stesso account nelle due app" "[[ \$out == *'usano lo stesso account'* ]]"
check "doctor: aggiornamenti bloccati" "[[ \$out == *'non si aggiorna da sola'* ]]"

print b > "$LB/Contents/Resources/double-claude"
out=$($CS doctor)
check "doctor: launcher della 1.0" "[[ \$out == *'versione 1.0'* ]]"
rm "$LB/Contents/Resources/double-claude"; print -r -- 'do shell script "x > /dev/null 2>&1 &"' > "$LB/Contents/Resources/Scripts/main.scpt"
out=$($CS doctor)
check "doctor: launcher fatto a mano che lavora in background" "[[ \$out == *'non è di double-claude'* && \$out == *'in background'* ]]"

sed -i.bak 's/^DC_ICON_LABELS=.*/DC_ICON_LABELS=both/' $H/.config/double-claude/config
out=$($CS --yes apply app)
check "etichette: annunciate da apply" "[[ \$out == *'etichette sulle icone: Work, Personal'* ]]"
check "etichette: icona del launcher nuova e valida" "! cmp -s '$SRC/Contents/Resources/electron.icns' '$LB/Contents/Resources/applet.icns' && sips -g pixelWidth '$LB/Contents/Resources/applet.icns' >/dev/null 2>&1"
check "etichette: icona personalizzata sulla copia" "[[ -f '$CL/Icon'$'\\r' ]]"
out=$($CS doctor)
check "doctor: etichetta sulla copia" "[[ \$out == *'etichetta Personal sull'* ]]"
rm -rf "$CL"; FAKE_DIALOG=Riapri $CS open b >/dev/null
check "copia rifatta al clic: l'etichetta torna" "[[ -f '$CL/Contents/Info.plist' && -f '$CL/Icon'$'\\r' ]]"
sed -i.bak 's/^DC_ICON_LABELS=.*/DC_ICON_LABELS=a/' $H/.config/double-claude/config
$CS --yes apply app >/dev/null
check "etichetta solo su A: via da copia e launcher di B, resta sul launcher di A" "[[ ! -f '$CL/Icon'$'\\r' ]] && cmp -s '$SRC/Contents/Resources/electron.icns' '$LB/Contents/Resources/applet.icns' && ! cmp -s '$SRC/Contents/Resources/electron.icns' '$LA/Contents/Resources/applet.icns'"
check "copia senza segno di icona personalizzata" "! xattr -p com.apple.FinderInfo '$CL' 2>/dev/null | grep -q '04 00'"
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$CL"
out=$($CS doctor)
check "doctor: icona rotta (segno senza file) riconosciuta" "[[ \$out == *'il Dock mostra una cartella'* ]]"
sed -i.bak 's/^DC_ICON_LABELS=.*/DC_ICON_LABELS=none/' $H/.config/double-claude/config
$CS --yes apply app >/dev/null
out=$($CS doctor)
check "apply app ripara l'icona rotta anche senza etichette" "[[ \$out != *'il Dock mostra una cartella'* ]] && ! xattr -p com.apple.FinderInfo '$CL' 2>/dev/null | grep -q '04 00'"
fi

# ---------------------------------------------------------------- scenario 5: lingua
print "Scenario 5: lingua"
export HOME=$T/eve; H=$HOME; mkdir -p $H/Documents/work/app $H/Documents/side; cd $H
print '{"oauthAccount":{"emailAddress":"eve@example.org"}}' > $H/.claude.json
out=$(DC_LANG= LANG=en_US.UTF-8 $CS help)
check "inglese con LANG=en_US" "[[ \$out == *'two Claude accounts on the same Mac'* ]]"
out=$(DC_LANG= LANG=it_IT.UTF-8 $CS help)
check "italiano con LANG=it_IT" "[[ \$out == *'due account Claude sullo stesso Mac'* ]]"
out=$(DC_LANG= LANG=it_IT.UTF-8 $CS --lang en help)
check "--lang en vince sulla lingua del sistema" "[[ \$out == *'two Claude accounts'* ]]"
printf '2\nwork\npersonal\n3\n~/Documents/work\ny\ny\nn\n' | DC_LANG=en $CS init > $T/init-en.txt 2>&1
check "init in inglese" "grep -q 'Where are you starting from' $T/init-en.txt && grep -q 'Dedicated folders' $T/init-en.txt && grep -q 'configuration saved' $T/init-en.txt"
check "risposte y accettate" "grep -q 'DC_MODULES=(shell move deny' $H/.config/double-claude/config"
out=$(DC_LANG=en $CS doctor)
check "doctor in inglese" "[[ \$out == *'Deny rules and reads'* && \$out == *'things to fix'* ]]"
out=$(DC_LANG=en $CS plan)
check "plan in inglese, anche il blocco per .zshrc" "[[ \$out == *'nothing is changed'* && \$out == *'works only in ~/Documents/work. Use claude-personal here.'* ]]"
sed -i.bak 's/^DC_LANG=.*/DC_LANG=it/' $H/.config/double-claude/config
out=$(DC_LANG= LANG=en_US.UTF-8 $CS doctor)
check "DC_LANG=it nella configurazione vince sul sistema" "[[ \$out == *'Divieti e letture'* ]]"
DC_LANG=en $CS --yes apply shell >/dev/null
r=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude x" 2>&1)
check "messaggio del .zshrc nella lingua di apply" "[[ \$r == *'claude: works only in ~/Documents/work. Use claude-personal here.'* ]]"

print "\n$pass passati, $fail falliti"
(( fail == 0 ))
