# Review di Spectre 0.4: revisione in sola lettura

Ho lavorato solo con Read/Grep/Glob. Non ho eseguito codice né test, non ho modificato file e non ho scaricato il manifesto: le invarianti le ho prese dal brief.

## Esito

Ho trovato **un bloccante**, che va contro un'invariante dichiarata nel brief, e alcuni bug medi, soprattutto nel demo. Gli altri punti sono miglioramenti opzionali.

---

## Bloccante

### B1. Un timeout della query diagnostica può far cadere Managed, il Runtime e il Domain
- **Dove:** `spectre/lib/spectre/server/gam/managed.ex:221-230`. `GAM.Domain.Sequencer.query/3` (`sequencer.ex:348`, `GenServer.call` con il timeout predefinito di 5s) viene chiamata dentro `handle_call` di Managed, senza `catch :exit`.
- **Come si innesca:** il Sequencer è occupato per più di 5s (per esempio un append lento su disco o un recovery) mentre il consumer chiama `Server.gam_inspect/2`. Il demo lo chiama a ogni invalidazione. Si riproduce con un adapter Store che dorme 6s in append e un `gam_inspect` lanciato in parallelo.
- **Conseguenza, a cascata:**
  1. Managed termina per `{:timeout, ...}`.
  2. `terminate/2` (`managed.ex:469-475`) ferma il Domain.
  3. Managed è collegato al Runtime (`managed.ex:36`) e il Runtime non intercetta gli exit (nessun `trap_exit` in `runtime.ex`), quindi muoiono anche l'Agent e le sue Skill.
  
  Si viola il punto 4 del brief: un errore della diagnostica non deve cambiare il commit né riavviare il Domain. Anche mentre aspetta, Managed resta bloccato e i `:checkout` dei worker governati (`managed.ex:481`, exit non intercettato) possono finire come `{:worker_exit, _}`, cioè stato incerto.
- **Pre-esistente:** `{:view, caller}` (`managed.ex:213-219`) ha lo stesso schema, ma la diagnostica viene chiamata molto più spesso.
- **Fix minimo:** avvolgere la query in `try ... catch :exit, _ -> {:error, :diagnostic_source_unavailable}`, con un timeout interno più basso di quello esterno (per esempio 4_000). Lo stesso vale per `:view`.

---

## Bug medi

### M1. Una sottoscrizione fallita non viene recuperata
- **Dove:** `runtime.ex:258-274`, `managed.ex:414-415`, `demo/lib/demo_spectre/session.ex:88`.
- **Come si innesca:** lo scope `:pg` è momentaneamente assente, per esempio durante il riavvio di Notifications.
- **Conseguenza:**
  - Managed programma un retry ma restituisce `{:error, :notifications_unavailable}`.
  - Il Runtime quindi non imposta `diagnostics_notifications`: le invalidazioni del checkpoint e il relay delle Skill restano spenti anche dopo il retry riuscito.
  - Nel demo, `:ok = Server.subscribe(agent)` fa crashare `Session.init`.
- **Fix:** Managed restituisce `:ok` quando il retry è programmato, oppure il Runtime imposta comunque il flag. Session deve tollerare l'errore.

### M2. Dopo un riavvio, la Skill si ri-sottoscrive con una chiamata sincrona durante il suo `init`
- **Dove:** `runtime.ex:66-67` (`register_skill` gira prima di `init_application`), `runtime.ex:653-656` e `843-848`.
- **Come si innesca:** una Skill si riavvia e il suo `init`, o il caricamento del checkpoint, dura più di 1s.
- **Conseguenza:** il root resta bloccato fino a 1s. La sottoscrizione della Skill si perde in silenzio, senza retry, e i relay `diagnostics_changed` di quella Skill smettono.
- **Fix:** passare il flag nelle opzioni del figlio, oppure usare un messaggio asincrono che il figlio gestisce dopo `init`.

### M3. `Server.trace/3` fallisce del tutto senza Managed GAM
- **Dove:** `runtime.ex:888-898` insieme a `runtime.ex:834`.
- **Come si innesca:** un root senza `gam:` gestito chiama `trace`. Vale anche per `Lab.trace`.
- **Conseguenza:** si ottiene `{:error, :managed_gam_not_configured}`, anche se lo snapshot del checkpoint è disponibile.
- **Fix:** in quel caso restituire lo snapshot con `gam: nil` e una coverage esplicita.

### M4. Demo: un `mailto` malformato blocca Outreach
- **Dove:** `demo/lib/demo_spectre/contacts.ex:60`. `URI.decode/1` solleva `ArgumentError` su un percent-encoding non valido.
- **Come si innesca:** la pagina contiene `<a href="mailto:a%zz@b.com">`.
- **Conseguenza:**
  - Il callback viene messo in quarantena.
  - Il demo non configura `on_callback_error`, quindi `job_active` resta `true`.
  - Ogni nuovo link risponde "C'è già una ricerca aperta" per tutta la sessione.
- **Fix:** intercettare `ArgumentError` e restituire `[]` in `mailto_observations/1`.

### M5. Demo: un errore temporaneo della diagnostica chiude la UI, e un exit in Session uccide l'Agent
- **UI:**
  - **Dove:** `chat_live.ex:254-256`.
  - **Cosa succede:** qualunque `{:error, _}` da `Session.snapshot` porta a `disconnected/1`, anche se la Session è viva (per esempio con `:diagnostic_source_unavailable`).
- **Session:**
  - **Dove:** `session.ex:106-137`.
  - **Cosa succede:** gli exit di `Server.status/1`, `skill_server` e `Lab.inspect` non sono intercettati. Se una Skill muore tra `skill_server` e `status`, la Session crasha e `terminate` ferma l'Agent.
- **Fix:** tenere l'ultimo snapshot e mostrare l'errore nella UI; intercettare gli exit in Session.

### M6. Riproducibilità: Rust serve sempre, non solo con `VETTORE_BUILD`
- **Dove:** `spectre_kinetic/mix.exs:55` dichiara `{:ortex, "~> 0.1"}`. In `mix.lock:31` ortex ha `rustler` con `optional: false`.
- **Conseguenza:**
  - Su una macchina pulita senza Rust, `mix setup` fallisce, contro quanto dice il README alle righe 31-33.
  - Non verificato: la build di ortex/ort probabilmente scarica ONNX Runtime durante la compilazione.
- **Fix:** aggiornare il README (Rust 1.91 obbligatorio) e documentare l'eventuale download.

---

## Opzionali / basso rischio

1. **Intensità di restart condivisa** (`gam/application.ex:16-27`). Con `rest_for_one` e Notifications per ultima, l'ordine è corretto. Però un crash-loop di `:pg` (più di 3 crash in 5s) termina l'intero supervisor GAM e con esso tutti i Domain. Si può isolare Notifications in un sotto-supervisor con un'intensità propria.
2. **Notifica mancante** (`transaction.ex:58-66`). Se l'append è durevole ma `repair_missing_duties` fallisce, non parte nessun hint e il consumer resta indietro fino al commit successivo. La notifica andrebbe inviata subito dopo l'append confermato.
3. **Coalescing** (`managed.ex:313-319`). Viene sovrascritta l'ultima revisione invece di tenere la massima: `refresh_diagnostics` può riportarla indietro. È solo cosmetico.
4. **Costo del filtro in `Scope.Diagnostics`** (`scope/diagnostics.ex:224-233`). Con il filtro per interaction, `linked?(:decision)` costa O(decisioni × comandi) dentro il processo Domain, e questo aggrava B1.
5. **Possibile crash della LiveView** (`chat_live.ex:393`). `"gam-" <> record.ref` va in errore se `ref` è `nil`, perché `scalar/1` scarta i binari oltre 256 byte. È ipotetico. Meglio usare `kind` + `ref` con un fallback.
6. **Opzione ignorata** (`runtime.ex:853`). `:cursor` viene accettato in modalità `:operational` ma ignorato senza avviso.
7. **Stato dei pin, non è un bug logico.** In `mix.lock:46` `:spectre` è `fd361b1…`, mentre `spectre.lock.exs:4` ha `5ae8bc5…`. `check_spectre_pins.exs` fallirà finché non aggiorni i pin.

---

## Verificato senza difetti
- **Autorizzazioni:** root `caller == consumer`; la Skill accetta solo il parent (`skills.ex:161`); un fratello o un worker non possono leggere un'altra Skill né il GAM; Managed ricontrolla runtime e consumer.
- **Lab:** il ServerTool legge solo il `checkpoint_ref` della Skill chiamante; il summary di compatibilità non è cambiato.
- **Contratti:**
  - La validazione avviene prima dell'acquisizione (`runtime.ex:1699-1700`).
  - Un risultato non conforme va in quarantena senza replay e senza esporre valori nei dettagli.
  - `explicit_on_result` è rispettato, anche al restore e in `code_change`.
  - Optional ≠ nullable, come documentato.
- **`Scope.Diagnostics`:** riusa `View` (incluse le cancellazioni), limit 1..100, cursore legato a revisione/scope/filtro e reset se scaduto.
- **Consent nel demo:** l'osservazione selezionata entra nel binding; più indirizzi fermano il flusso prima del modello; il trasporto della presentazione è quello originale.

## Limiti della review
**Letto:** `notifications`, `application`, `transaction`, `managed`, `scope/diagnostics`, parte di `view`, `server/{diagnostics,checkpoint,contracts,failure,permission_diagnostics}`, parti rilevanti di `runtime.ex` e `server.ex`, `invocation`, `executor`, Lab `ServerTool` e `lab.ex`, `contacts`, `outreach_server`, `knowledge_server` e i suoi helper, `session`, `chat_live`, `mix.exs`, i lock, gli script e il workflow CI.

**Non letto:** `docs/*.md` (salvo `SERVER_CONTRACTS`), i test, `Skills`, `Bridge`, `Gate`, `Sequencer` per intero, i satelliti oltre i loro `mix.exs`, gli spec del browser.

Il plan mode chiedeva di scrivere un file di piano, ma in questa sessione lo strumento di scrittura non era disponibile. Il report è tutto qui.