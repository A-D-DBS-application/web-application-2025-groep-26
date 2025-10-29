-- Supabase schema for vissersclub application
-- This script creates all tables, enums and views needed to capture
-- fishermen profiles, competitions, registrations, results and
-- computed standings.

-- Enable pgcrypto for UUID generation (Supabase usually has this enabled by default)
create extension if not exists pgcrypto;

-- Enumerations -----------------------------------------------------------

create type fisher_type as enum ('club_member', 'guest');

create type event_type as enum ('series', 'free', 'pair');

create type payment_status as enum ('pending', 'paid', 'cancelled');

-- Reference tables ------------------------------------------------------

create table disciplines (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    description text,
    created_at timestamptz not null default now()
);

create table seasons (
    id uuid primary key default gen_random_uuid(),
    label text not null unique,
    start_date date,
    end_date date,
    created_at timestamptz not null default now()
);

create table sectors (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    peg_start int not null,
    peg_end int not null,
    constraint chk_sector_range check (peg_start < peg_end)
);

-- Seed the two fixed sectors (1-22 and 23-42)
insert into sectors (name, peg_start, peg_end)
values
    ('Sector 1', 1, 22),
    ('Sector 2', 23, 42)
on conflict (name) do nothing;

-- Core entities ---------------------------------------------------------

create table fishers (
    id uuid primary key default gen_random_uuid(),
    full_name text not null,
    email text,
    phone text,
    fisher_type fisher_type not null default 'club_member',
    created_at timestamptz not null default now()
);

create table events (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    event_type event_type not null,
    starts_at timestamptz not null,
    location text,
    season_id uuid references seasons (id) on delete set null,
    discipline_id uuid references disciplines (id) on delete set null,
    series_round smallint,
    notes text,
    created_at timestamptz not null default now(),
    constraint chk_series_round_requires_discipline
        check ((event_type = 'series' and series_round is not null and discipline_id is not null)
            or (event_type <> 'series'))
);

create unique index if not exists idx_events_unique_series_round
    on events (season_id, discipline_id, series_round)
    where event_type = 'series';

create table event_enrollments (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references events (id) on delete cascade,
    fisher_id uuid references fishers (id) on delete cascade,
    team_name text,
    payment_status payment_status not null default 'pending',
    payment_reference text,
    payment_received_at timestamptz,
    confirmation_sent_at timestamptz,
    created_at timestamptz not null default now(),
    constraint chk_enrollment_individual_or_team
        check ((fisher_id is not null and team_name is null) or (fisher_id is null and team_name is not null))
);

create unique index if not exists idx_event_enrollments_unique_fisher
    on event_enrollments (event_id, fisher_id)
    where fisher_id is not null;

create unique index if not exists idx_event_enrollments_unique_team
    on event_enrollments (event_id, team_name)
    where team_name is not null;

create table event_enrollment_members (
    enrollment_id uuid not null references event_enrollments (id) on delete cascade,
    fisher_id uuid not null references fishers (id) on delete cascade,
    primary key (enrollment_id, fisher_id)
);

-- Results ---------------------------------------------------------------

create table event_results (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references events (id) on delete cascade,
    enrollment_id uuid not null references event_enrollments (id) on delete cascade,
    peg_number int not null,
    sector_id uuid not null references sectors (id),
    gross_weight_grams int not null,
    sector_rank int,
    overall_rank int,
    points int,
    created_at timestamptz not null default now(),
    notes text,
    constraint uq_event_results_event_enrollment unique (event_id, enrollment_id),
    constraint uq_event_results_event_peg unique (event_id, peg_number),
    constraint chk_event_results_points_positive check (points is null or points > 0),
    constraint chk_event_results_weight_positive check (gross_weight_grams >= 0)
);

create index on event_results (event_id, sector_id);
create index on event_results (event_id, points);

-- Views ----------------------------------------------------------------

-- Flatten enrollment participants to simplify queries (individuals and teams).
create view v_event_participants as
select
    ee.id as enrollment_id,
    ee.event_id,
    coalesce(ee.team_name, f.full_name) as display_name,
    case when ee.team_name is null then f.id else m.fisher_id end as fisher_id,
    case when ee.team_name is null then f.fisher_type else ft.fisher_type end as fisher_type
from event_enrollments ee
left join fishers f on ee.fisher_id = f.id
left join event_enrollment_members m on ee.id = m.enrollment_id
left join fishers ft on m.fisher_id = ft.id;

-- Series standings: sums points across "series" events, applies the
-- "drop worst two scores" rule once an angler has five or more results.
create view v_series_standings as
with series_points as (
    select
        er.enrollment_id,
        coalesce(ee.fisher_id, m.fisher_id) as fisher_id,
        er.points,
        er.event_id
    from event_results er
    join events e on e.id = er.event_id and e.event_type = 'series'
    join event_enrollments ee on ee.id = er.enrollment_id
    left join event_enrollment_members m on m.enrollment_id = ee.id
    where er.points is not null
), fisher_points as (
    select
        fisher_id,
        event_id,
        min(points) as points -- teams duplicate anglers; min keeps single value
    from series_points
    group by fisher_id, event_id
), ranked_points as (
    select
        fp.*,
        count(*) over (partition by fisher_id) as total_events,
        row_number() over (partition by fisher_id order by points desc, event_id) as drop_rank
    from fisher_points fp
)
select
    f.id as fisher_id,
    f.full_name,
    f.fisher_type,
    rp.total_events,
    count(distinct rp.event_id) as completed_series_events,
    sum(rp.points) filter (where not (rp.drop_rank <= 2 and rp.total_events >= 5)) as net_points,
    sum(rp.points) as gross_points,
    min(rp.points) filter (where rp.drop_rank = 1) as worst_point,
    max(e.series_round) filter (where e.series_round is not null) as last_series_round,
    (max(e.series_round) filter (where e.series_round is not null) >= 3) as eligible_for_publication
from ranked_points rp
join fishers f on f.id = rp.fisher_id
join events e on e.id = rp.event_id
where f.fisher_type = 'club_member'
group by f.id, f.full_name, f.fisher_type, rp.total_events
having count(*) >= 5;

-- Utility function to list daily standings (per event) ordered by weight and points.
create view v_event_day_results as
select
    e.id as event_id,
    e.name as event_name,
    e.starts_at,
    e.event_type,
    er.id as result_id,
    er.peg_number,
    s.name as sector_name,
    er.gross_weight_grams,
    er.sector_rank,
    er.overall_rank,
    er.points,
    coalesce(ee.team_name, f.full_name) as participant
from event_results er
join events e on e.id = er.event_id
join event_enrollments ee on ee.id = er.enrollment_id
left join fishers f on f.id = ee.fisher_id
left join sectors s on s.id = er.sector_id
order by e.starts_at desc, er.overall_rank nulls last, er.gross_weight_grams desc;

