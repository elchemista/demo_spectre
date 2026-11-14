# Follow-up su B1 e M1–M6: nessun bloccante rimasto

Ho lavorato solo in lettura: niente comandi, niente modifiche, nessun test eseguito da me. Ho riletto le sezioni corrette di `managed.ex`, `runtime.ex` (diagnostica e sottoscrizioni) e `transaction.ex`. Nel demo ho letto `contacts.ex`, `session.ex` e `chat_live.ex`. Dei test ho verificato solo che esistano e cosa coprono, senza leggerli tutti:
- core: `managed_runtime_test.exs:922` e `:958`, più gli altri file che hai citato;
- demo: `contacts_test.exs:56-64`.

## Stato dei finding precedenti

| ID | Esito | Dove l'ho verificato |
|---|---|---|
| **B1** | **Risolto** | `managed.ex:437-469`: lettori con `spawn_monitor`, massimo 4. Ogni lettore ha `GenServer.call(..., 3_500)` con `catch :exit` e un watchdog a 4s; restano separati da `state.workers`. L'autorizzazione avviene prima del lancio (`213-227`). Il DOWN di un lettore si chiude in `367-372`, e in `terminate` le risposte in sospeso ricevono errore (`535-541`). `Managed` non chiama più direttamente il Domain, quindi un timeout non può farlo crashare. |
| **M1** | **Risolto** | `managed.ex:429-432` restituisce `:ok` e programma il retry. Al rientro, l'aggiornamento della head è asincrono (`426`, `483-484`). Il Runtime imposta il flag (`runtime.ex:265-267`). La Session riprova senza crashare (`session.ex:215-225`). |
| **M2** | **Risolto** | `runtime.ex:854-858` invia un messaggio asincrono. Il figlio lo gestisce dopo `init` e verifica `skill_parent == {parent, token}` (`664-673`); con un token diverso il messaggio viene ignorato. Il nuovo clause non va in conflitto con i catch-all a 4 elementi (`690-691`). |
| **M3** | **Risolto** | `runtime.ex:910-917` restituisce `gam: nil` con coverage esplicita. Il cursore in modalità operational viene rifiutato (`864`). |
| **Opz. 2** | **Risolto** | `transaction.ex:81-85`: la notifica parte dentro `append_verified` per ogni batch confermato, prima della riparazione. Le leggi di ammissione e fold del kernel non cambiano. |
| **Opz. 3** | **Risolto** | `managed.ex:323` usa `max`. |
| **M4** | **Risolto** | `contacts.ex:59-73`: guard sul `%` malformato più `rescue ArgumentError`. I test coprono `a%zz`, `a%` e `a%0`. |
| **M5** | **Risolto** | Session: le letture passano da `diagnostic_read` con `catch :exit` (`208-213`) e gli snapshot delle Skill restituiscono `{:error, _}` (`191-206`). LiveView: un errore non disconnette più, conserva lo stato e mostra un avviso con «Riprova» (`255-264`, `385-392`). Disconnette solo il `:DOWN` della Session (`332`). Gli id dei record ora includono kind e ref, oppure ordinale e hash (`403-422`). |
| **M6** | Chiuso secondo il tuo report | Non l'ho riverificato. |
| **Opz. 1** | Accetto la classificazione | È un limite di disponibilità OTP, non un confine di autorità. |

Prendo atto anche di due chiarimenti: la discrepanza dei pin era una lettura concorrente, e su Elixir 1.20 `URI.decode` non solleva eccezioni.

## Residui minori, nessuno bloccante

1. **`gam_view` senza `catch`**
   - **Dove:** `runtime.ex:237` usa `managed_call` invece di `diagnostic_managed_call`.
   - **Rischio:** dato che `Managed` ora risponde entro circa 4s, l'exit può arrivare solo se `Managed` è morto o sovraccarico. Se è morto, il Runtime muore comunque perché collegato.
   - **Fix:** usare `diagnostic_managed_call` per coerenza.
2. **Refresh di rientro scartato quando lo slot è pieno**
   - **Dove:** `managed.ex:441-443`.
   - **Rischio:** con 4 letture in corso al momento del rientro, il refresh della head viene scartato senza retry. L'invalidazione persa si recupera al commit successivo o con «Riprova». È solo cosmetico.
3. **Nessun retry automatico nella LiveView dopo un errore di `:refresh`**
   - **Dove:** `chat_live.ex:259`.
   - **Rischio:** se l'errore cade proprio mentre viene creata un'attesa di consenso, il pulsante di conferma (che si basa su `@pending`) può restare assente fino al prossimo `diagnostics_changed` o a «Riprova». Il consenso testuale («confermo») continua a funzionare.
   - **Fix opzionale:** un solo retry con backoff.
4. **Root bloccato dalla lettura su una Skill** (pre-esistente)
   - **Dove:** `runtime.ex:886`.
   - **Rischio:** la lettura usa il timeout predefinito di 5s e può bloccare il root se il figlio è occupato. L'exit viene catturato e solo il consumer autenticato può innescarla.

## Conclusione

Non trovo nessun bloccante concreto nuovo che un utente possa innescare. B1 e M1–M5 risultano corretti nel codice attuale. L'esito dei test resta quello che hai riportato tu.