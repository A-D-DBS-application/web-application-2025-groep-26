# Supabase schema

This directory contains the SQL needed to bootstrap the database for the vissersclub app.  
Apply `schema.sql` in Supabase (SQL editor or migration) to create the tables, enums, and views used by the application.

## Highlights

- **Disciplines & seasons** – keep the three club disciplines and yearly seasons organised.
- **Sectors** – pre-seeded with the fixed 1–22 and 23–42 peg ranges.
- **Events** – supports series (reeksen), vrije wedstrijden, and koppels via `event_type`.
- **Inschrijvingen** – track payment status, confirmations, and optional team-inschrijvingen.
- **Resultaten** – store sector/overall rankings, weights, and derived punten.
- **Views** – helper views for dagklassementen en klassement met aftrek van twee slechtste resultaten.

Update the script if Supabase introduces breaking changes to enums or extensions.
