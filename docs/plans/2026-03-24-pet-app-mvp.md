# PetNote MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a HarmonyOS high-fidelity runnable prototype for the PetNote MVP with fixed bottom navigation, a global add sheet, pet-centered records, and local rule-based overview reports.

**Architecture:** Replace the starter page with an in-app shell that composes five fixed bottom-nav destinations and modal add flows. Keep business logic in typed models, a local in-memory store, and pure analysis services so the prototype feels complete now and can later swap in real HarmonyOS persistence, reminder, picker, and export implementations.

**Tech Stack:** ArkTS, ArkUI (Stage model), Hypium, HarmonyOS module resources, local mock data, pure service utilities

---

### Task 1: Build And Verification Scaffold

**Files:**
- Create: `scripts/run.ps1`
- Modify: `F:\HarmonyProject\Pet\docs\plans\2026-03-24-pet-app-mvp.md`
- Test: `entry/src/test/LocalUnit.test.ets`

**Step 1: Write the failing verification expectation**

Replace the template local test with a simple smoke expectation that references the upcoming app title constant so the current project no longer relies on placeholder assertions.

```ts
import { APP_TITLE } from '../main/ets/common/AppConstants'

it('exposes app title', 0, () => {
  expect(APP_TITLE).assertEqual('PetNote')
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL because `scripts/run.ps1` and `AppConstants` do not exist yet.

**Step 3: Write minimal implementation**

Create `scripts/run.ps1` so later tasks can use one command for compile/test verification. The first version can:

- validate required tooling is available
- run local tests when `-Mode test`
- run project build when `-Mode build`

**Step 4: Run verification to confirm the script executes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: The script launches and reports the next missing implementation clearly.

**Step 5: Commit**

```bash
git add scripts/run.ps1 entry/src/test/LocalUnit.test.ets
git commit -m "chore: add pet app verification scaffold"
```

### Task 2: Core Models And Seed Data

**Files:**
- Create: `entry/src/main/ets/common/AppConstants.ets`
- Create: `entry/src/main/ets/models/PetModels.ets`
- Create: `entry/src/main/ets/common/SampleData.ets`
- Test: `entry/src/test/models/PetModels.test.ets`

**Step 1: Write the failing test**

```ts
import { samplePets, sampleTodos, sampleReminders, sampleRecords } from '../../main/ets/common/SampleData'

it('builds sample PetNote data', 0, () => {
  expect(samplePets.length).assertLarger(0)
  expect(sampleTodos.length).assertLarger(0)
  expect(sampleReminders.length).assertLarger(0)
  expect(sampleRecords.length).assertLarger(0)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL with missing model and sample data imports.

**Step 3: Write minimal implementation**

Define typed interfaces / enums for:

- `Pet`
- `TodoItem`
- `Reminder`
- `PetRecord`
- `OverviewRange`
- common status / type enums

Add small but realistic seed data covering at least:

- 2 pets
- mixed todos, reminders, and overdue items
- several pet records spanning multiple dates

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS for the new sample-data test.

**Step 5: Commit**

```bash
git add entry/src/main/ets/common/AppConstants.ets entry/src/main/ets/models/PetModels.ets entry/src/main/ets/common/SampleData.ets entry/src/test/models/PetModels.test.ets
git commit -m "feat: add PetNote models and sample data"
```

### Task 3: Local Overview Analyzer

**Files:**
- Create: `entry/src/main/ets/services/OverviewAnalyzer.ets`
- Test: `entry/src/test/services/OverviewAnalyzer.test.ets`

**Step 1: Write the failing test**

```ts
import { buildOverviewSnapshot } from '../../main/ets/services/OverviewAnalyzer'
import { samplePets, sampleTodos, sampleReminders, sampleRecords } from '../../main/ets/common/SampleData'

it('builds AI-style sections for a selected range', 0, () => {
  const snapshot = buildOverviewSnapshot('7d', samplePets, sampleTodos, sampleReminders, sampleRecords)
  expect(snapshot.sections.length).assertEqual(4)
  expect(snapshot.disclaimer.length).assertLarger(0)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL because the analyzer does not exist.

**Step 3: Write minimal implementation**

Create pure functions that:

- filter data by selected time range
- compute completion / postpone / skip counts
- detect notable pet activity and missing records
- emit four stable sections: key changes, care observations, risk alerts, suggested actions
- append a fixed compliance disclaimer

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS for overview analyzer tests.

**Step 5: Commit**

```bash
git add entry/src/main/ets/services/OverviewAnalyzer.ets entry/src/test/services/OverviewAnalyzer.test.ets
git commit -m "feat: add local overview analyzer"
```

### Task 4: App Store For Navigation And CRUD

**Files:**
- Create: `entry/src/main/ets/stores/AppStore.ets`
- Test: `entry/src/test/stores/AppStore.test.ets`

**Step 1: Write the failing test**

```ts
import { createAppStore } from '../../main/ets/stores/AppStore'

it('adds todo items and updates checklist state', 0, () => {
  const store = createAppStore()
  const count = store.getTodos().length
  store.addTodo('Brush Luna', 'pet-1')
  expect(store.getTodos().length).assertEqual(count + 1)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL because the app store is missing.

**Step 3: Write minimal implementation**

Create a local store that owns:

- active tab
- selected pet
- add-sheet state
- pets, todos, reminders, records
- CRUD helpers for add / edit status transitions
- derived getters for checklist sections and overview snapshot

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS for store behavior tests.

**Step 5: Commit**

```bash
git add entry/src/main/ets/stores/AppStore.ets entry/src/test/stores/AppStore.test.ets
git commit -m "feat: add pet app local store"
```

### Task 5: Shared UI Building Blocks

**Files:**
- Create: `entry/src/main/ets/common/Theme.ets`
- Create: `entry/src/main/ets/components/AppShell.ets`
- Create: `entry/src/main/ets/components/BottomNavBar.ets`
- Create: `entry/src/main/ets/components/ActionSheet.ets`
- Create: `entry/src/main/ets/components/SectionCard.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Step 1: Write the failing UI expectation**

Add a light smoke test that references a fixed nav item label exported from the shell.

```ts
import { NAV_ITEMS } from '../../main/ets/components/BottomNavBar'

it('uses fixed bottom navigation labels', 0, () => {
  expect(NAV_ITEMS.length).assertEqual(5)
  expect(NAV_ITEMS[2].label).assertEqual('+')
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL because the shared shell components do not exist.

**Step 3: Write minimal implementation**

Build a reusable shell with:

- fixed five-slot bottom navigation
- center plus button
- content slot for current page
- reusable section cards and action-sheet layout

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS and project still compiles.

**Step 5: Commit**

```bash
git add entry/src/main/ets/common/Theme.ets entry/src/main/ets/components/AppShell.ets entry/src/main/ets/components/BottomNavBar.ets entry/src/main/ets/components/ActionSheet.ets entry/src/main/ets/components/SectionCard.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: add pet app shell components"
```

### Task 6: Checklist Page

**Files:**
- Create: `entry/src/main/ets/pages/ChecklistPage.ets`
- Create: `entry/src/main/ets/components/ChecklistItemCard.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Step 1: Write the failing test**

```ts
import { groupChecklistSections } from '../../main/ets/stores/AppStore'

it('groups checklist items into today upcoming and overdue', 0, () => {
  const sections = groupChecklistSections()
  expect(sections.length).assertEqual(3)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL because grouping helper or page wiring is incomplete.

**Step 3: Write minimal implementation**

Render checklist content with:

- date header and summary chips
- today / upcoming / overdue sections
- inline buttons for complete / postpone / skip
- pet identity displayed on linked items

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS and checklist UI renders without ArkTS compile errors.

**Step 5: Commit**

```bash
git add entry/src/main/ets/pages/ChecklistPage.ets entry/src/main/ets/components/ChecklistItemCard.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: add checklist page"
```

### Task 7: Overview Page

**Files:**
- Create: `entry/src/main/ets/pages/OverviewPage.ets`
- Create: `entry/src/main/ets/components/OverviewRangeSelector.ets`
- Create: `entry/src/main/ets/components/OverviewSectionCard.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Step 1: Write the failing test**

```ts
import { OVERVIEW_RANGES } from '../../main/ets/services/OverviewAnalyzer'

it('supports all overview time ranges', 0, () => {
  expect(OVERVIEW_RANGES.length).assertEqual(5)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL until the page and exports are wired.

**Step 3: Write minimal implementation**

Render:

- time-range selector
- AI-style summary header
- four overview report sections
- disclaimer text
- empty state when data is insufficient

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS and overview page compiles.

**Step 5: Commit**

```bash
git add entry/src/main/ets/pages/OverviewPage.ets entry/src/main/ets/components/OverviewRangeSelector.ets entry/src/main/ets/components/OverviewSectionCard.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: add overview page"
```

### Task 8: Pets Page And Pet Detail

**Files:**
- Create: `entry/src/main/ets/pages/PetsPage.ets`
- Create: `entry/src/main/ets/components/PetListCard.ets`
- Create: `entry/src/main/ets/components/PetDetailPanel.ets`
- Create: `entry/src/main/ets/components/RecordListCard.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Step 1: Write the failing test**

```ts
import { createAppStore } from '../../main/ets/stores/AppStore'

it('filters records by selected pet', 0, () => {
  const store = createAppStore()
  const pet = store.getPets()[0]
  expect(store.getRecordsForPet(pet.id).length).assertLarger(0)
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL until per-pet record selectors exist.

**Step 3: Write minimal implementation**

Render:

- pet list landing state
- selected pet detail panel
- basic profile, health/feeding, recent reminders, records
- empty state when no records exist

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS and pets detail view compiles.

**Step 5: Commit**

```bash
git add entry/src/main/ets/pages/PetsPage.ets entry/src/main/ets/components/PetListCard.ets entry/src/main/ets/components/PetDetailPanel.ets entry/src/main/ets/components/RecordListCard.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: add pets page and detail"
```

### Task 9: Me Page And Global Add Forms

**Files:**
- Create: `entry/src/main/ets/pages/MePage.ets`
- Create: `entry/src/main/ets/components/forms/AddTodoForm.ets`
- Create: `entry/src/main/ets/components/forms/AddReminderForm.ets`
- Create: `entry/src/main/ets/components/forms/AddRecordForm.ets`
- Create: `entry/src/main/ets/components/forms/AddPetForm.ets`
- Modify: `entry/src/main/ets/components/ActionSheet.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Step 1: Write the failing test**

```ts
import { ADD_ACTIONS } from '../../main/ets/components/ActionSheet'

it('keeps four fixed global add actions', 0, () => {
  expect(ADD_ACTIONS.length).assertEqual(4)
  expect(ADD_ACTIONS[0].label).assertEqual('新增待办')
})
```

**Step 2: Run test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: FAIL until the fixed action sheet exports exist.

**Step 3: Write minimal implementation**

Add:

- fixed add sheet with four actions
- lightweight forms for todo, reminder, record, and pet
- `Me` page with permission, privacy, backup, and about cards
- current-pet prefill behavior without changing action labels

**Step 4: Run test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: PASS and add flows compile.

**Step 5: Commit**

```bash
git add entry/src/main/ets/pages/MePage.ets entry/src/main/ets/components/forms/AddTodoForm.ets entry/src/main/ets/components/forms/AddReminderForm.ets entry/src/main/ets/components/forms/AddRecordForm.ets entry/src/main/ets/components/forms/AddPetForm.ets entry/src/main/ets/components/ActionSheet.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: add me page and global add forms"
```

### Task 10: Final Integration And Verification

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/resources/base/element/color.json`
- Modify: `entry/src/main/resources/base/element/float.json`

**Step 1: Write the final verification checklist**

Document the final smoke checks in comments or a short checklist note:

- bottom navigation switches correctly
- `+` action opens everywhere
- checklist actions mutate local state
- overview range changes update report
- pets page opens details and records

**Step 2: Run build verification**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode build`
Expected: Build succeeds with no ArkTS compile errors.

**Step 3: Run test verification**

Run: `powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Mode test`
Expected: All local tests pass.

**Step 4: Perform manual smoke verification**

Check the prototype in HarmonyOS Preview or on-device for:

- navigation feel
- action-sheet flow
- overview rendering
- pet detail readability

**Step 5: Commit**

```bash
git add entry/src/main/ets/pages/Index.ets entry/src/main/resources/base/element/string.json entry/src/main/resources/base/element/color.json entry/src/main/resources/base/element/float.json
git commit -m "feat: finalize PetNote MVP prototype"
```
