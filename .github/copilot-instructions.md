# Copilot instructions – Maiburg Transport interface

AL-extensie voor Business Central (prefix `MBT`, ID-range 52100–52149) die magazijnverzendingen koppelt aan transporteurs (DHL, Bumbal, Claassen, Van der Werff).

## Documentatie van functionele wijzigingen (verplicht)

Het bestand [`docs/Functionele-wijzigingen.md`](../docs/Functionele-wijzigingen.md) beschrijft alle functionele wijzigingen van deze extensie en **moet bij elke wijziging worden bijgewerkt**.

- Werk dit bestand in dezelfde wijziging bij als de code, zonder dat de gebruiker erom vraagt.
- Een wijziging is *functioneel* als ze merkbaar is voor gebruikers of beheerders: nieuwe/gewijzigde velden, pagina's, acties, meldingen, instellingen, rechten, berichtinhoud naar een transporteur, berekeningen, validaties, bugfixes met gedragsverandering. Zuiver technische refactorings zonder gedragsverandering hoeven er niet in.
- Zet nieuwe wijzigingen onder de kop van de huidige versie uit `app.json`; maak bij een versieverhoging een nieuwe kop `## <versie>` bovenaan (onder *Nog niet uitgebracht*) en verplaats ongepubliceerde items daarnaartoe.
- Schrijf in het Nederlands, per onderwerp (bijv. Tussenscherm, DHL, Bumbal, Instellingen, Labels), beknopt en vanuit het perspectief van de gebruiker/beheerder: *wat* is er gewijzigd en *waarom/effect*.
- Pas ook de sectie "basisversie" aan als de beschreven basisfunctionaliteit verandert.

## Conventies

- Teksten in de UI en foutmeldingen zijn Nederlands; houd `Caption`, `ToolTip` en `Label`-teksten consistent met bestaande objecten.
- Bij nieuwe of gewijzigde teksten het vertaalbestand in `Translations\` bijwerken.
- Nieuwe objecten gebruiken het prefix `MBT` en een ID uit de range in `app.json`.
- Secrets (wachtwoorden, API-keys, tokens) alleen in Isolated Storage via `MBT Transport Cred. Mgt.`, nooit in code of logboek.
- Nieuwe transporteurs implementeren de interface `MBT ITransportConnector`.
