# PetNote MVP Design

## Goal

Build a HarmonyOS high-fidelity runnable prototype for a PetNote app focused on daily task handling, pet-centered records, and local AI-style care summaries.

## Product Scope

### In Scope

- Offline-first PetNote tool
- `Checklist` page for todos and reminders
- `Overview` page for local rule-generated AI-style summaries
- `Pets` page for pet list and per-pet details
- `Me` page for settings, permissions, privacy, and backup placeholders
- Global `+` action for adding todo, reminder, record, and pet
- Pet records kept inside each pet detail page

### Out of Scope

- Real AI model integration
- Third-party merchant, booking, or transaction features
- Online diagnosis or medical conclusions
- Cross-device sync in this phase
- Real export / picker / notification capability in this phase beyond service-layer placeholders

## Information Architecture

Bottom navigation has five fixed items:

1. `Checklist`
2. `Overview`
3. `+`
4. `Pets`
5. `Me`

The center `+` button is a fixed global action and always opens the same four-entry action sheet:

- Add Todo
- Add Reminder
- Add Record
- Add Pet

The entries never change by page. If the user launches an add flow from a pet detail page, the current pet can be prefilled, but the menu remains fixed.

## Page Design

### Checklist

Purpose: show what the user needs to do now.

Modules:

- Header with date and quick summary
- Today section
- Upcoming section
- Overdue section
- Inline actions: complete, postpone, skip

Rules:

- Cards show pet avatar/name when linked to a pet
- Interactions should require as few page jumps as possible

### Overview

Purpose: provide AI-style care summary and suggestions, using local rules instead of a real model.

Time ranges:

- Last 7 days
- Last 1 month
- Last 3 months
- Last 6 months
- Last 1 year

Output sections:

- Key Changes
- Care Observations
- Risk Alerts
- Suggested Actions

Boundary:

- Content is for daily care reference only
- No diagnosis, treatment conclusion, or veterinarian replacement wording

### Pets

Purpose: manage pets and view pet-centered information.

Pets landing page:

- Pet list cards
- Quick add pet entry

Pet detail sections:

- Basic Profile
- Health and Feeding
- Recent Reminders
- Records

Records live under the current pet and include:

- Medical note
- Receipt
- Image
- Test result
- Other

### Me

Purpose: hold non-business settings and app-level information.

Modules:

- Notification / permission guidance
- Backup and restore placeholders
- Privacy note
- About

## Core Data Model

### Pet

- id
- name
- avatar
- species / breed
- sex
- birthday / age
- neutered status
- weight
- feeding preferences
- allergies / restrictions
- note

### Reminder

- id
- petId
- kind
- title
- scheduledAt
- recurrence
- status
- note

### Todo

- id
- petId
- title
- dueDate
- priority
- status
- note

### PetRecord

- id
- petId
- type
- title
- recordDate
- summary
- tags
- attachmentPlaceholder
- note

### OverviewSnapshot

Computed locally from pets, reminders, todos, and records for the selected time range.

## Interaction Design

### Global Add Flows

- Add Todo: title, pet, date, priority, note
- Add Reminder: title, pet, type, time, recurrence, note
- Add Record: pet, type, title, date, summary, attachment placeholder, note
- Add Pet: name, avatar placeholder, breed, sex, birthday/age, neutered status, weight, feeding preferences, allergies/restrictions, note

### Empty States

- No pets: prompt to add the first pet
- No checklist items: show calm empty state with add CTA
- Not enough overview data: explain more records are needed for better summaries
- No pet records: encourage adding the first record from pet detail

## Technical Design

Use a layered structure that keeps prototype UI fast to build while preserving future extension points:

- `pages/`: top-level page containers
- `components/`: reusable cards, chips, sheets, forms
- `models/`: typed data structures
- `stores/`: local state and view composition
- `services/`: persistence, reminder, overview analysis, export/share placeholders
- `common/`: constants, theme, sample data, format helpers

The first version uses local mock/sample data plus service abstractions so real HarmonyOS APIs can replace placeholder implementations later.

## Acceptance Criteria

- User can add, view, and edit pets
- User can add todos, reminders, and records and see them correctly grouped
- Checklist supports complete, postpone, and skip actions
- Overview can switch time ranges and generate local rule-based report content
- Pets page can open pet details and show per-pet records
- Global `+` button is always available and always shows the same four actions

## Implementation Notes

- Prefer high-fidelity UI and smooth flows over real system capability integration in this phase
- Keep service interfaces ready for later notification, picker, export, and sharing replacement
- Preserve the medical-compliance boundary in all summary copy
