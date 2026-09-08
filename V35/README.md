# Azure - Uppgift 2 (V35)
**IAM och Identitet**
#

**Namn:** Simon Fatty

**Repo:** https://github.com/02simfat/azure-MOV25

**Datum** 2026-08-06

# 1. Syfte
Syftet med denna uppgift är att bygga vidare på resursgruppenb från V34 och sätta upp en säker identitets- och behörighetsstruktur i Microsoft Entra ID för Novatrix. Behörigheterna har fördelats strikt utfrån årincipen om **Least Privliege** för att säkerställa att ingen användare har mer årkoimst än vad rollen kräver.

---


## 2. Infrastruktur och Resursgrupp
Ny infrastruktur har skapats i resursgruppen `rg-novatrix-v35` i Regionen `swedencentral` med hjälp av ett Powershell-Skript (`deploy.ps1`) och en cloud-init-konfiguration (`cloud-init.yaml`).

### Konfigurationer som har skapats:

* **Resursgrupp:** `rg-novatrix-v35`
* **Virtuell maskin:** `vm-novatrix-web` (Ubuntu 24.04, Standard_B2ats_v2)
* **Webbserver:** Nginx installerad automatiskt via `cloud-init.yaml`
* **Hanterad Identitet:** `id-novatrix-app` (User-assigned Managed Identity i `rg-novatrix-v35`)


---

## 3. Entra ID: Användare och Grupper

För att hantera åtkomsten på ett struktureart och skalvart sätt har roller inte Tilldelats ensklida personer utan till säkerhetsgrupper.

### Skapade användare:
* **Drift-Anna:** `drift-anna@simonfatty0202gmail.onmicrosoft.com`
* **Utveckling-Erik:** `Utveckling-erik@simonfatty0202gmail.onmicrosoft.com`

### Skapade säkerhetsgrupper:
1. **`Azure-Drift`** (medlemmen: `drift-anna`)
2. **`Azure-Utveckling`** (medlemmen: `Utveckling-erik`)

---

## 4. RBAC och Least Privilege 

Roller hhar tilldelats på **Resursgruppsnivå `rg-novatrix-v35`**. Inga tilldelningar har gjorts på prenumerationnivå eller direkt på enskulda användare.

### Översikt över RBAC-tilldelnigarr:
| Vem (Grupp) | Vad (Roll) | Var (Scope) | Motivering (Least Privilege) |
| :--- | :--- | :--- | :--- |
| **`Azure-Drift`** | **Deltagare (Contributor)** | Resursgrupp `rg-novatrix-v35` | Driftteam behöver kunna skapa, starta, stoppa och underhålla resurser (t.ex. VM:ar) för den dagliga driften, men behöver inte tilldela behörigheter till andra (saknar Owner-rättigheter). |
| **`Azure-Utveckling`** | **Läsare (Reader)** | Resursgrupp `rg-novatrix-v35` | Utvecklingsteam behöver öppenhet i miljöns status, konfigurationer och loggar för att felsöka sina applikationer, men ska inte kunna ändra, stoppa eller ta bort infrastruktur i produktion. |

### Motivering till Least Privlege-modellen:
1. **Varför grupper instället för personer?** Om en person slutar eller byter roll behöver vi bara flytta personen i Entra ID. man slipper ändra i själva Azure-resursenas behörighetlistor.
2. **VArför Resursgruppen som scope?** Genom att avgränsa behörigheterna til `rg-novatrix-v35` istället för hela prenumerationen förhindras att misstag i ett team påverkar andra resusgrupper eller miljöer i Azure.

---

## 5. Hanterade Identitet (Managed Idenity)

En användatilldelade hanterade identitet har förberetts för novatix formulärapplikation 

* **Namn:** `id-novatrix-app`
* **Resursgrupp:** `rg-novatrix-v35`
* **Region:** Sweden Central

![ `Managed-Identity.png`](Managed-Identity.png)

---

## 6. Verifering av Behörigheter 

För att verifera att behörigheterna begränsar användaran så gjodes 2 kontroller:

### Kontroll 1: Check Access (IAM)

Via Azure Portal > Åtkomstkontroll (IAM) kontrollerades åtkomsten för `Utveckling-erik`. Systemet bekräftade att han endast har rollen **Läsare (Reader)** via sin gruppmedlemskap i `Azure-Utveckling`.

![ `IAM-verifiering.png`](IAM-verifiering.png)
![ `IAM-Roller.png`](IAM-Roller.png)

### Kontroll 2: Test i portalen som begränsad användare
1. Inloggning skedde i ett InPrivate-fönster som **`Utveckling-erik@simonfatty0202gmail.onmicrosoft.com`**.
2. Navigering till resursgruppen `rg-novatrix-v35` och den virtuella maskinen `vm-novatrix-web` lyckades (Erik kan se alla resurser och deras status).
3. Ett försök gjordes att klicka på knappen **Stoppa** på den virtuella maskinen.
4. **Resultat:** Åtgärden nekas med felmeddelandet: > *"Det gick inte att stoppa den virtuella datorn... Klienten har inte behörighet att utföra åtgärden 'Microsoft.Compute/virtualMachines/deallocate/action'..."*

Detta verifierar att **Läsare**-rollen fungerar enligt Least Privilege och stoppar obehöriga ändringar i infrastrukturen.

![`Erik-stopVM-novatrix.png`](Erik-stopVM-novatrix.png)

![`Erik-rg-novatrix.png`](Erik-rg-novatrix.png)





