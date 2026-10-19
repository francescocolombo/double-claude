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
const a=process.argv.slice(2);j.mcpServers=j.mcpServers||{};
if(a[0]==='mcp'&&a[1]==='add-json'){if(j.mcpServers[a[2]]){process.exit(1)}j.mcpServers[a[2]]=JSON.parse(a[3]);}
else if(a[0]==='mcp'&&a[1]==='remove'){if(!j.mcpServers[a[2]])process.exit(1);delete j.mcpServers[a[2]];}
else if(a[0]==='mcp'&&a[1]==='list'){console.log(Object.keys(j.mcpServers).join('\n'));process.exit(0)}
fs.mkdirSync(require('path').dirname(f),{recursive:true});fs.writeFileSync(f,JSON.stringify(j,null,2));
EOF
chmod +x $T/bin/claude
export PATH=$T/bin:$PATH DC_SKIP_RUNNING_CHECK=1 NO_COLOR=1
[[ -n ${DC_TEST_JXA:-} ]] && unset DC_JS_RUNTIME || export DC_JS_RUNTIME=node
unset CLAUDE_CONFIG_DIR       # mai la config vera di chi lancia i test
export DC_APP=$T/nessuna-app   # i test non devono mai vedere la Claude.app vera del Mac

# ---------------------------------------------------------------- scenario 1: due account mescolati, zona di A
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
 "projects":{"$H/Documents/work":{},"$H/Documents/work/app":{},"$H":{},"$H/Documents/side":{}}}
EOF
print '{"permissions":{"allow":["Bash(ls:*)"]}}' > $H/.claude/settings.json
print -l 'export X=1' 'alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"' > $H/.zshrc
cd $H

printf '2\nwork\npersonal\n2\n~/Documents/work\nnotes\ns\ns\n' | $CS init >/dev/null
check "init salva la config" "[[ -f $H/.config/double-claude/config ]]"
check "zona di A e moduli scelti" "grep -q 'DC_ZONE_OWNER=a' $H/.config/double-claude/config && grep -q 'DC_MODULES=(shell move mcp deny)' $H/.config/double-claude/config"
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
check "divieti di B sulla zona di lavoro" "grep -q 'Read(~/Documents/work/\*\*)' $H/.claude-personal/settings.json"
$CS --yes apply shell >/dev/null
check "blocco zshrc idempotente" "[[ \$(grep -c '>>> double-claude' $H/.zshrc) -eq 1 ]]"
sed -i.bak '/^alias/d' $H/.zshrc
r1=$(cd $H/Documents/work/app && zsh -c "source $H/.zshrc; claude-personal x" 2>&1)
check "B rifiutato nella zona di A" "[[ \$r1 == *'nella zona work'* ]]"
r2=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude x" 2>&1)
check "A rifiutato fuori dalla zona" "[[ \$r2 == *'fuori dalla zona work'* ]]"
r3=$(cd $H/Documents/side && zsh -c "source $H/.zshrc; claude-personal mcp list" 2>&1)
check "B usa la sua config fuori zona" "[[ \$r3 == *notes* ]]"
out=$($CS doctor)
check "doctor dopo apply: resta solo il login di B" "[[ \$out == *'1 cosa da sistemare'* ]]"

n=$(ls -d $H/.config/double-claude/backups/*.noindex | wc -l)
print "$n\ns" | $CS restore >/dev/null 2>&1   # il più vecchio
check "restore al primo backup rimette le chat in A" "[[ \$(ls $H/.claude/projects | wc -l) -eq 5 ]]"
check "restore toglie la config di B che non esisteva" "[[ ! -d $H/.claude-personal ]]"

# ---------------------------------------------------------------- scenario 2: un solo account, zona di B, risposte da stdin
print "Scenario 2: un solo account, zona di B"
export HOME=$T/sam; H=$HOME; mkdir -p $H/Projects/acme; cd $H
print '{"oauthAccount":{"emailAddress":"sam@example.org"},"mcpServers":{}}' > $H/.claude.json
printf '1\npersonal\nacme\n3\n~/Projects/acme\nn\ns\n' | $CS init >/dev/null
check "start=one, zona di B" "grep -q 'DC_START=one' $H/.config/double-claude/config && grep -q 'DC_ZONE_OWNER=b' $H/.config/double-claude/config"
check "move non scelto" "grep -q 'DC_MODULES=(shell deny)' $H/.config/double-claude/config"
plan=$($CS plan)
check "claude rifiutato dentro la zona di B" "[[ \$plan == *'claude: questa cartella è nella zona acme'* ]]"

# ---------------------------------------------------------------- scenario 3: zone saltate
print "Scenario 3: zone saltate (--yes)"
export HOME=$T/lee; H=$HOME; mkdir -p $H/Documents/any; cd $H
print '{"oauthAccount":{"emailAddress":"lee@example.org"}}' > $H/.claude.json
$CS --yes init >/dev/null
check "--yes non crea zone" "grep -q 'DC_ZONE_OWNER=none' $H/.config/double-claude/config && grep -q 'DC_ZONE_DIRS=()' $H/.config/double-claude/config"
check "senza zone lo spostamento non è scelto" "! grep -q 'DC_MODULES=.*move' $H/.config/double-claude/config"
out=$($CS doctor)
check "doctor spiega che non ci sono zone" "[[ \$out == *'Nessuna zona'* ]]"
$CS --yes apply >/dev/null
r1=$(cd $H/Documents/any && zsh -c "source $H/.zshrc; whence -w claude-personal; whence -w claude" 2>&1)
check "senza zone: solo la funzione di B, claude resta quello vero" "[[ \$r1 == *'claude-personal: function'* && \$r1 != *'claude: function'* ]]"

# ---------------------------------------------------------------- scenario 4: app Desktop (strumenti macOS simulati)
print "Scenario 4: app Desktop"
if ! whence -p plutil >/dev/null; then print "  - saltato: serve plutil (macOS)"
else
export HOME=$T/kim; H=$HOME; mkdir -p $H; cd $H
M=$T/mac; mkdir -p $M
mkplist() { print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>$1</string><key>CFBundleShortVersionString</key><string>$2</string></dict></plist>" > $3; }
SRC=$T/apps/Claude.app; mkdir -p $SRC/Contents/{MacOS,Resources}; mkplist com.anthropic.claudefordesktop 2.9.1 $SRC/Contents/Info.plist
print icona > $SRC/Contents/Resources/electron.icns; print bin > $SRC/Contents/MacOS/Claude
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

printf '1\nwork\npersonal\n1\ns\ns\ns\n' | $CS init >/dev/null
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
fi

print "\n$pass passati, $fail falliti"
(( fail == 0 ))
