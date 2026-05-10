-- Pokemon Dex Database Schema
-- All competitive game data for Pokemon across all generations.

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
-- NOTE: foreign_keys is a per-connection setting; every client that opens
-- this database must re-issue PRAGMA foreign_keys=ON to enforce FK checks.

-- ============================================================
-- Reference tables
-- ============================================================

CREATE TABLE generations (
    id   INTEGER PRIMARY KEY,           -- 1..9
    name TEXT NOT NULL UNIQUE            -- "I", "II", ..., "IX"
);

CREATE TABLE games (
    id            INTEGER PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    generation_id INTEGER NOT NULL REFERENCES generations(id)
);
CREATE INDEX idx_games_generation ON games(generation_id);

CREATE TABLE types (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE move_categories (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE              -- "Physical", "Special", "Status", "???"
);

CREATE TABLE growth_rates (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE              -- "Fast", "Medium Fast", "Medium Slow", "Slow", "Erratic", "Fluctuating"
);

CREATE TABLE pokemon_colors (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE egg_groups (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- One row per (region, generation). Regional dexes were re-cut in remakes —
-- Hoenn was renumbered between RSE (Gen 3) and ORAS (Gen 6); Johto between
-- GSC (Gen 2) and HGSS (Gen 4) — so a "Hoenn dex slot" is only well-defined
-- once you fix the generation. National is pinned to Gen 1 (the canonical
-- numbering, since National only appends and never renumbers).
CREATE TABLE regional_dexes (
    id            INTEGER PRIMARY KEY,
    name          TEXT NOT NULL,           -- "National", "Kanto", "Hoenn", "Crown Tundra", ...
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    UNIQUE(name, generation_id)
);
CREATE INDEX idx_regional_dexes_generation ON regional_dexes(generation_id);

CREATE TABLE abilities (
    id                       INTEGER PRIMARY KEY,
    name                     TEXT NOT NULL UNIQUE,
    description              TEXT,
    generation_introduced_id INTEGER REFERENCES generations(id)
);
CREATE INDEX idx_abilities_generation ON abilities(generation_introduced_id);

CREATE TABLE items (
    id                       INTEGER PRIMARY KEY,
    name                     TEXT NOT NULL UNIQUE,
    description              TEXT,
    generation_introduced_id INTEGER REFERENCES generations(id)
);
CREATE INDEX idx_items_generation ON items(generation_introduced_id);

CREATE TABLE regulations (
    id            INTEGER PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    generation_id INTEGER REFERENCES generations(id),
    valid_from    TEXT,                    -- ISO 8601 date or NULL
    valid_until   TEXT
);
CREATE INDEX idx_regulations_generation ON regulations(generation_id);

-- ============================================================
-- Core species & forms
-- ============================================================

-- pokemon.id is an opaque surrogate. The National Dex number is stored in
-- pokedex_numbers (with dex_id pointing at the 'National' regional_dexes row),
-- alongside every other regional dex number. Do not assume pokemon.id matches
-- any in-game number.
CREATE TABLE pokemon (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL UNIQUE,
    category TEXT
);

-- Per-generation species attributes that have changed across games.
-- Examples: catch rate (some species rebalanced), base friendship (global
-- 70 -> 50 change in Gen 8), base experience yield (Gen 4 -> Gen 5 formula).
CREATE TABLE pokemon_per_gen (
    pokemon_id      INTEGER NOT NULL REFERENCES pokemon(id),
    generation_id   INTEGER NOT NULL REFERENCES generations(id),
    catch_rate      INTEGER CHECK(catch_rate IS NULL OR catch_rate BETWEEN 0 AND 255),
    base_friendship INTEGER,
    base_exp_yield  INTEGER,
    PRIMARY KEY (pokemon_id, generation_id)
);

CREATE TABLE pokemon_forms (
    id                       INTEGER PRIMARY KEY,
    pokemon_id               INTEGER NOT NULL REFERENCES pokemon(id),
    form_name                TEXT NOT NULL DEFAULT 'Default',
    form_kind                TEXT NOT NULL DEFAULT 'default'
                             CHECK(form_kind IN ('default','mega','primal','regional','gigantamax','cosmetic','other')),
    height_m                 REAL,
    weight_kg                REAL,
    color_id                 INTEGER REFERENCES pokemon_colors(id),
    generation_introduced_id INTEGER REFERENCES generations(id),
    -- Per-form biology: regional forms can carry different growth rates,
    -- hatch cycles, or gender ratios than their base species.
    male_eighths             INTEGER CHECK(male_eighths IS NULL OR male_eighths BETWEEN 0 AND 8),
                                                   -- 0 = always female, 8 = always male, NULL = genderless
    growth_rate_id           INTEGER REFERENCES growth_rates(id),
    hatch_cycles             INTEGER,
    UNIQUE(pokemon_id, form_name)
);
CREATE INDEX idx_pokemon_forms_pokemon ON pokemon_forms(pokemon_id);
CREATE INDEX idx_pokemon_forms_color ON pokemon_forms(color_id);
CREATE INDEX idx_pokemon_forms_generation ON pokemon_forms(generation_introduced_id);
CREATE INDEX idx_pokemon_forms_growth_rate ON pokemon_forms(growth_rate_id);
-- A pokemon has exactly one default form. Partial unique index enforces this
-- without restricting how many non-default forms (mega, regional, ...) exist.
CREATE UNIQUE INDEX uq_one_default_per_pokemon
    ON pokemon_forms(pokemon_id) WHERE form_kind = 'default';

-- ============================================================
-- Per-(form, generation) data
-- ============================================================

CREATE TABLE form_types (
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    type1_id      INTEGER NOT NULL REFERENCES types(id),
    type2_id      INTEGER REFERENCES types(id),
    PRIMARY KEY (form_id, generation_id),
    CHECK(type2_id IS NULL OR type2_id <> type1_id)
);
CREATE INDEX idx_form_types_type1 ON form_types(type1_id);
CREATE INDEX idx_form_types_type2 ON form_types(type2_id);

CREATE TABLE form_base_stats (
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    hp            INTEGER NOT NULL,
    attack        INTEGER NOT NULL,
    defense       INTEGER NOT NULL,
    sp_attack     INTEGER NOT NULL,
    sp_defense    INTEGER NOT NULL,
    speed         INTEGER NOT NULL,
    PRIMARY KEY (form_id, generation_id)
);

CREATE TABLE form_ev_yield (
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    hp            INTEGER NOT NULL DEFAULT 0,
    attack        INTEGER NOT NULL DEFAULT 0,
    defense       INTEGER NOT NULL DEFAULT 0,
    sp_attack     INTEGER NOT NULL DEFAULT 0,
    sp_defense    INTEGER NOT NULL DEFAULT 0,
    speed         INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (form_id, generation_id)
);

CREATE TABLE form_abilities (
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    role          TEXT NOT NULL CHECK(role IN ('primary','secondary','hidden')),
    ability_id    INTEGER NOT NULL REFERENCES abilities(id),
    PRIMARY KEY (form_id, generation_id, role)
);
CREATE INDEX idx_form_abilities_ability ON form_abilities(ability_id);

-- ============================================================
-- Pokedex
-- ============================================================

CREATE TABLE pokedex_numbers (
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id),
    dex_id     INTEGER NOT NULL REFERENCES regional_dexes(id),
    dex_number INTEGER NOT NULL,
    PRIMARY KEY (pokemon_id, dex_id)
);
-- Each (dex revision, slot) holds exactly one species. This invariant only
-- holds once dexes are keyed per-generation (see regional_dexes); the older
-- single-Hoenn / single-Johto layout had collisions across remakes.
CREATE UNIQUE INDEX uq_pokedex_numbers_slot ON pokedex_numbers(dex_id, dex_number);

-- Keyed by form so regional / alternate-form variants (e.g., Galarian Ponyta)
-- can carry their own flavor text; species without form-specific entries just
-- attach to the default form.
CREATE TABLE pokedex_entries (
    form_id    INTEGER NOT NULL REFERENCES pokemon_forms(id),
    game_id    INTEGER NOT NULL REFERENCES games(id),
    entry_text TEXT    NOT NULL,
    PRIMARY KEY (form_id, game_id)
);
CREATE INDEX idx_pokedex_entries_game ON pokedex_entries(game_id);

-- ============================================================
-- Egg groups
-- ============================================================

-- Keyed per generation: assignments shifted in Gen 6 (Fairy egg group added,
-- several species reassigned).
CREATE TABLE pokemon_egg_groups (
    pokemon_id    INTEGER NOT NULL REFERENCES pokemon(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    egg_group_id  INTEGER NOT NULL REFERENCES egg_groups(id),
    PRIMARY KEY (pokemon_id, generation_id, egg_group_id)
);
CREATE INDEX idx_pokemon_egg_groups_group ON pokemon_egg_groups(egg_group_id);

-- ============================================================
-- Moves
-- ============================================================

CREATE TABLE moves (
    id                       INTEGER PRIMARY KEY,
    name                     TEXT NOT NULL UNIQUE,
    type_id                  INTEGER REFERENCES types(id),
    category_id              INTEGER REFERENCES move_categories(id),
    power                    INTEGER,
    accuracy                 INTEGER CHECK(accuracy IS NULL OR accuracy BETWEEN 0 AND 100),
    pp                       INTEGER,
    priority                 INTEGER NOT NULL DEFAULT 0,
    effect                   TEXT,
    generation_introduced_id INTEGER REFERENCES generations(id)
);
CREATE INDEX idx_moves_type ON moves(type_id);
CREATE INDEX idx_moves_priority ON moves(priority);

-- ============================================================
-- TM/HM/TR Index
-- ============================================================

CREATE TABLE tm_index (
    tm_number TEXT NOT NULL,
    game_id   INTEGER NOT NULL REFERENCES games(id),
    move_id   INTEGER NOT NULL REFERENCES moves(id),
    PRIMARY KEY (tm_number, game_id)
);
CREATE INDEX idx_tm_index_move ON tm_index(move_id);
CREATE INDEX idx_tm_index_game ON tm_index(game_id);

-- ============================================================
-- Learnsets (consolidated)
-- ============================================================

-- learnsets.tm_number duplicates the (game, move) -> tm_number relation in
-- tm_index. It is denormalized intentionally: learnsets are stored at
-- generation granularity, but TM numbering can vary per game within a
-- generation, so the row records the specific TM slot used to teach the move.
CREATE TABLE learnsets (
    id            INTEGER PRIMARY KEY,
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_id INTEGER NOT NULL REFERENCES generations(id),
    move_id       INTEGER NOT NULL REFERENCES moves(id),
    method        TEXT NOT NULL CHECK(method IN
                  ('levelup','tm','egg','tutor','prior-gen','other')),
    level         INTEGER CHECK(level IS NULL OR level BETWEEN 0 AND 100),
                                -- 0 = starting move or learned on evolution
    tm_number     TEXT,
    detail        TEXT,
    -- Method dispatch: each method binds exactly the columns it needs.
    -- 'levelup' requires level (and forbids tm_number); 'tm' requires
    -- tm_number (and forbids level); other methods forbid both.
    CHECK (
        (method = 'levelup' AND level IS NOT NULL AND tm_number IS NULL) OR
        (method = 'tm'      AND level IS NULL     AND tm_number IS NOT NULL) OR
        (method NOT IN ('levelup','tm') AND level IS NULL AND tm_number IS NULL)
    )
);
CREATE UNIQUE INDEX uq_learnsets ON learnsets(
    form_id, generation_id, move_id, method, COALESCE(level, -1));
CREATE INDEX idx_learnsets_move_gen ON learnsets(move_id, generation_id);
CREATE INDEX idx_learnsets_form_method ON learnsets(form_id, method);

-- ============================================================
-- Evolution
-- ============================================================

-- An evolution_methods row is the "edge" between two forms; the conditions
-- under which the edge fires are stored in evolution_conditions.
CREATE TABLE evolution_methods (
    id                       INTEGER PRIMARY KEY,
    from_form_id             INTEGER NOT NULL REFERENCES pokemon_forms(id),
    to_form_id               INTEGER NOT NULL REFERENCES pokemon_forms(id),
    generation_introduced_id INTEGER REFERENCES generations(id)
);
CREATE INDEX idx_evolution_from ON evolution_methods(from_form_id);
CREATE INDEX idx_evolution_to ON evolution_methods(to_form_id);

-- A single evolution can have multiple conditions that must all hold (e.g.,
-- "level up at night while holding Razor Claw" = three rows). Each row picks
-- the typed value column appropriate to its kind; the others are NULL.
CREATE TABLE evolution_conditions (
    evolution_id INTEGER NOT NULL REFERENCES evolution_methods(id),
    kind         TEXT NOT NULL CHECK(kind IN (
                 'level','friendship','use_item','held_item','trade',
                 'knows_move','time_of_day','location','gender',
                 'species_in_party','weather','beauty','affection','other')),
    int_value    INTEGER,                              -- level, friendship, beauty, ...
    item_id      INTEGER REFERENCES items(id),         -- use_item, held_item
    move_id      INTEGER REFERENCES moves(id),         -- knows_move
    species_id   INTEGER REFERENCES pokemon(id),       -- species_in_party
    text_value   TEXT,                                 -- time_of_day, location, gender, ...
    -- Kind dispatch: each kind binds exactly the typed-value column(s) it
    -- needs and forbids the rest. 'trade' is a bare condition with no value
    -- (a trade with a held item is split into 'trade' + 'held_item' rows).
    -- 'friendship'/'beauty'/'affection' have an implicit per-generation
    -- threshold; int_value is optional and only set when the row records
    -- a non-default threshold.
    CHECK (
        (kind = 'level'
            AND int_value IS NOT NULL
            AND item_id IS NULL AND move_id IS NULL AND species_id IS NULL AND text_value IS NULL) OR
        (kind IN ('friendship','beauty','affection')
            AND item_id IS NULL AND move_id IS NULL AND species_id IS NULL AND text_value IS NULL) OR
        (kind IN ('use_item','held_item')
            AND item_id IS NOT NULL
            AND int_value IS NULL AND move_id IS NULL AND species_id IS NULL AND text_value IS NULL) OR
        (kind = 'knows_move'
            AND move_id IS NOT NULL
            AND int_value IS NULL AND item_id IS NULL AND species_id IS NULL AND text_value IS NULL) OR
        (kind = 'species_in_party'
            AND species_id IS NOT NULL
            AND int_value IS NULL AND item_id IS NULL AND move_id IS NULL AND text_value IS NULL) OR
        (kind IN ('time_of_day','location','gender','weather','other')
            AND text_value IS NOT NULL
            AND int_value IS NULL AND item_id IS NULL AND move_id IS NULL AND species_id IS NULL) OR
        (kind = 'trade'
            AND int_value IS NULL AND item_id IS NULL AND move_id IS NULL AND species_id IS NULL AND text_value IS NULL)
    )
);
CREATE UNIQUE INDEX uq_evolution_conditions ON evolution_conditions(
    evolution_id, kind,
    COALESCE(int_value, -1),
    COALESCE(item_id, -1),
    COALESCE(move_id, -1),
    COALESCE(species_id, -1),
    COALESCE(text_value, '')
);
CREATE INDEX idx_evolution_conditions_evolution ON evolution_conditions(evolution_id);
-- Partial indexes on the sparse typed-value columns: most rows have these as
-- NULL (only set when kind matches), so partial indexes are smaller and skip
-- the irrelevant rows entirely.
CREATE INDEX idx_evolution_conditions_item ON evolution_conditions(item_id)
    WHERE item_id IS NOT NULL;
CREATE INDEX idx_evolution_conditions_move ON evolution_conditions(move_id)
    WHERE move_id IS NOT NULL;
CREATE INDEX idx_evolution_conditions_species ON evolution_conditions(species_id)
    WHERE species_id IS NOT NULL;

-- Mega, Primal, and Gigantamax forms are temporary battle transformations,
-- not evolution endpoints. Reject any attempt to point an evolution row at one.
CREATE TRIGGER trg_evolution_no_battle_forms_insert
BEFORE INSERT ON evolution_methods
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'evolution endpoint cannot be a mega/primal/gigantamax form')
    WHERE EXISTS (
        SELECT 1 FROM pokemon_forms
        WHERE id IN (NEW.from_form_id, NEW.to_form_id)
          AND form_kind IN ('mega', 'primal', 'gigantamax')
    );
END;

CREATE TRIGGER trg_evolution_no_battle_forms_update
BEFORE UPDATE OF from_form_id, to_form_id ON evolution_methods
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'evolution endpoint cannot be a mega/primal/gigantamax form')
    WHERE EXISTS (
        SELECT 1 FROM pokemon_forms
        WHERE id IN (NEW.from_form_id, NEW.to_form_id)
          AND form_kind IN ('mega', 'primal', 'gigantamax')
    );
END;

-- ============================================================
-- Game availability
-- ============================================================

CREATE TABLE game_availability (
    id         INTEGER PRIMARY KEY,
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id),
    game_id    INTEGER NOT NULL REFERENCES games(id),
    method     TEXT
);
CREATE UNIQUE INDEX uq_game_availability ON game_availability(
    pokemon_id, game_id, COALESCE(method, ''));
CREATE INDEX idx_game_availability_game ON game_availability(game_id);

-- ============================================================
-- Type matchups
-- ============================================================

CREATE TABLE type_matchups (
    attacking_type_id INTEGER NOT NULL REFERENCES types(id),
    defending_type_id INTEGER NOT NULL REFERENCES types(id),
    generation_id     INTEGER NOT NULL REFERENCES generations(id),
    multiplier        REAL NOT NULL CHECK(multiplier IN (0, 0.25, 0.5, 1, 2, 4)),
    PRIMARY KEY (attacking_type_id, defending_type_id, generation_id)
);
CREATE INDEX idx_type_matchups_atk ON type_matchups(attacking_type_id, generation_id);

-- ============================================================
-- Champions tables
-- ============================================================

CREATE TABLE champions_learnset (
    form_id       INTEGER NOT NULL REFERENCES pokemon_forms(id),
    move_id       INTEGER NOT NULL REFERENCES moves(id),
    regulation_id INTEGER NOT NULL REFERENCES regulations(id),
    PRIMARY KEY (form_id, move_id, regulation_id)
);
CREATE INDEX idx_champions_learnset_move ON champions_learnset(move_id);

CREATE TABLE champions_legality (
    form_id        INTEGER NOT NULL REFERENCES pokemon_forms(id),
    regulation_id  INTEGER NOT NULL REFERENCES regulations(id),
    is_legal       INTEGER NOT NULL DEFAULT 1 CHECK(is_legal IN (0,1)),
    version_added  TEXT,
    notes          TEXT,
    PRIMARY KEY (form_id, regulation_id)
);
