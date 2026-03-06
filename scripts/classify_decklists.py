#!/usr/bin/env python3
"""
Deck Archetype Auto-Classification Script

Analyzes decklist_json in results table and assigns archetypes based on signature cards.
Only processes UNKNOWN archetype results that have decklists.

Usage:
    python scripts/classify_decklists.py --dry-run    # Preview changes
    python scripts/classify_decklists.py              # Apply changes

Prerequisites:
    pip install psycopg2-binary python-dotenv
    NEON_HOST and NEON_PASSWORD env vars required (in .env file)
"""

import argparse
import os
import sys
import json
from collections import Counter
from dotenv import load_dotenv

load_dotenv()


def get_connection():
    """Connect to Neon PostgreSQL."""
    import psycopg2

    host = os.getenv("NEON_HOST")
    dbname = os.getenv("NEON_DATABASE", "neondb")
    user = os.getenv("NEON_USER")
    password = os.getenv("NEON_PASSWORD")

    if not host or not password:
        print("Error: NEON_HOST and NEON_PASSWORD env vars required")
        sys.exit(1)

    return psycopg2.connect(
        host=host,
        dbname=dbname,
        user=user,
        password=password,
        port=5432,
        sslmode="require"
    )

# Classification rules: list of (archetype_name, required_cards, min_matches)
# required_cards can be a list of card name patterns (substring match)
# min_matches is how many of the required cards must be present
# ORDER MATTERS - more specific rules should come before general ones
CLASSIFICATION_RULES = [
    # ==========================================================================
    # SPECIFIC DECK ARCHETYPES (order matters - more specific first)
    # ==========================================================================

    # Bagra Army (Blastmon variant with Bagramon/DarkKnightmon)
    ("Bagra Army", ["Blastmon", "Bagramon", "DarkKnightmon"], 2),
    ("Bagra Army", ["Bagramon", "DarkKnightmon"], 2),

    # Rocks (Sunarizamon line with Magneticdramon/Pyramidimon)
    ("Rocks", ["Sunarizamon", "Landramon", "Proganomon", "Magneticdramon"], 3),
    ("Rocks", ["Sunarizamon", "Landramon", "Pyramidimon"], 3),
    ("Rocks", ["Blastmon", "Sunarizamon", "Magneticdramon"], 3),
    ("Rocks", ["Blastmon", "Sunarizamon", "Pyramidimon"], 3),

    # Millenniummon (Jogress with Machinedramon + Kimeramon)
    ("Millenniummon", ["Millenniummon", "Machinedramon", "Kimeramon"], 3),
    ("Millenniummon", ["Millenniummon", "Kimeramon"], 2),
    ("Millenniummon", ["Millenniummon", "Vademon", "Kimeramon"], 2),

    # Magnamon Armors (Veemon armor evolution)
    ("Magnamon Armors", ["Magnamon", "Veemon", "Flamedramon"], 3),
    ("Magnamon Armors", ["Magnamon", "Veemon", "Shadramon"], 3),
    ("Magnamon Armors", ["Magnamon", "Veemon", "Lighdramon"], 3),
    ("Magnamon Armors", ["Magnamon", "Lighdramon"], 2),

    # ExMaquinamon (Machine deck)
    ("ExMaquinamon", ["ExMaquinamon", "Maquinamon", "Maneuvermon"], 2),
    ("ExMaquinamon", ["ExMaquinamon", "Maquinamon", "Turbomon"], 2),

    # Ice-Snow (Bulucomon line)
    ("Ice-Snow", ["Bulucomon", "Paledramon"], 2),
    ("Ice-Snow", ["Bulucomon", "Frigimon", "Paledramon"], 2),

    # Dark Animals (MadLeomon)
    ("Dark Animals", ["MadLeomon", "MadLeomon: Armed Mode"], 2),
    ("Dark Animals", ["MadLeomon", "Sangloupmon", "Dracmon"], 2),

    # Hina Linkz (Vorvomon/Jazamon + Hina tamer)
    ("Hina Linkz", ["Vorvomon", "Lavorvomon", "Hina Kurihara"], 2),
    ("Hina Linkz", ["Jazamon", "Jazardmon", "Hina Kurihara"], 2),
    ("Hina Linkz", ["Vorvomon", "Jazamon", "Hina Kurihara"], 2),

    # Dark Masters (all 4)
    ("Dark Masters", ["MetalSeadramon", "Puppetmon", "Machinedramon", "Piedmon"], 3),
    ("Dark Masters", ["Apocalymon", "MetalSeadramon", "Puppetmon"], 2),
    ("Dark Masters", ["Apocalymon", "Machinedramon", "Piedmon"], 2),

    # Appmon boss variants (specific before generic)
    ("Poseidomon", ["Poseidomon", "Oujamon", "Dokamon"], 2),
    ("Poseidomon", ["Poseidomon", "Consulmon"], 2),
    ("Galacticmon", ["Galacticmon", "Cometmon"], 2),
    ("Galacticmon", ["Galacticmon", "Dokamon", "Consulmon"], 2),

    # Myotismon Loop
    ("Myotismon Loop", ["MaloMyotismon", "Myotismon", "Arukenimon", "Mummymon"], 3),

    # Medusamon (Elizamon line)
    ("Medusamon", ["Medusamon", "Lamiamon", "Elizamon"], 3),
    ("Medusamon", ["Medusamon", "Lamiamon", "Dimetromon"], 3),

    # Royal Base (Bug/Bee deck - TigerVespamon line)
    ("Royal Base", ["TigerVespamon", "CannonBeemon", "FunBeemon"], 3),
    ("Royal Base", ["TigerVespamon", "Waspmon", "FunBeemon"], 3),
    ("Royal Base", ["QueenBeemon", "CannonBeemon", "FunBeemon"], 3),

    # Gigaseadramon (Seadramon line)
    ("Gigaseadramon", ["GigaSeadramon", "MegaSeadramon", "Seadramon"], 3),
    ("Gigaseadramon", ["MetalSeadramon", "MegaSeadramon", "Seadramon"], 3),

    # Hudiemon (includes Gotsumon) — MUST come before Shakkoumon
    # BT20 Hudiemon decks include Shakkoumon as tech
    ("Hudiemon", ["Hudiemon", "Wormmon", "Gotsumon"], 2),
    ("Hudiemon", ["Hudiemon", "Wormmon"], 2),
    ("Hudiemon", ["Hudiemon", "Gotsumon"], 2),
    ("Hudiemon", ["Hudiemon", "Shakkoumon"], 2),

    # Shakkoumon
    ("Shakkoumon", ["Shakkoumon", "Angemon", "Patamon"], 2),
    ("Shakkoumon", ["Shakkoumon", "Ankylomon"], 2),

    # Galaxy (Celestial/Lunar theme)
    ("Galaxy", ["Lunamon", "Coronamon", "Apollomon"], 2),
    ("Galaxy", ["Lunamon", "Dianamon", "Galaxymon"], 2),
    ("Galaxy", ["Coronamon", "Apollomon", "Dianamon"], 2),

    # Fenriloogamon
    ("Fenriloogamon", ["Fenriloogamon", "Cerberusmon", "Kazuchimon"], 2),
    ("Fenriloogamon", ["Fenriloogamon: Takemikazuchi"], 1),

    # Xros Heart (Shoutmon line)
    ("Xros Heart", ["OmniShoutmon", "Shoutmon"], 2),

    # Creepymon
    ("Creepymon", ["Creepymon", "SkullSatamon"], 2),

    # Beelzemon (includes Wizardmon/Baalmon variants)
    ("Beelzemon", ["Beelzemon", "Impmon", "Wizardmon"], 2),
    ("Beelzemon", ["Beelzemon", "Impmon", "Baalmon"], 2),
    ("Beelzemon", ["Beelzemon", "Impmon"], 2),
    ("Beelzemon", ["Beelzemon: Blast Mode"], 1),

    # Gallantmon
    ("Gallantmon", ["Gallantmon", "Guilmon", "Growlmon"], 3),

    # Eaters — min=2 required: "Eater" substring matches "In-Between Theater"
    ("Eaters", ["Eater", "EDEN's Javelin"], 2),

    # Imperialdramon variants
    ("Imperialdramon (UG)", ["Imperialdramon", "Paildramon", "ExVeemon"], 3),
    ("Imperialdramon (PR)", ["Imperialdramon", "Stingmon", "Wormmon"], 3),
    ("Imperialdramon (PR)", ["Imperialdramon", "Dinobeemon", "Stingmon"], 3),
    ("Imperialdramon (PR)", ["Imperialdramon", "Shadramon", "Wormmon"], 3),

    # Jesmon
    ("Jesmon", ["Jesmon", "Sistermon", "Huckmon"], 2),

    # CS Mastemon (includes Gatomon/Salamon/Patamon variants)
    ("CS Mastemon", ["Mastemon", "Angewomon", "LadyDevimon"], 2),
    ("CS Mastemon", ["Mastemon", "Gatomon", "LadyDevimon"], 2),
    ("CS Mastemon", ["Mastemon", "Gatomon", "Salamon"], 2),
    ("CS Mastemon", ["Mastemon", "Gatomon", "Patamon"], 2),

    # Blue Flare
    ("Blue Flare", ["MetalGreymon", "MailBirdramon", "Greymon"], 3),

    # Leviamon
    ("Leviamon", ["Leviamon", "Gesomon", "Syakomon"], 2),

    # Lucemon
    ("Lucemon", ["Lucemon", "Lucemon: Chaos Mode", "Lucemon: Satan Mode"], 2),
    ("Lucemon", ["Lucemon: Chaos Mode", "Lucemon: Satan Mode"], 2),

    # Royal Knights (multiple Royal Knight Digimon + King Drasil)
    # MUST come before CS Alphamon and Chronicle to avoid misclassification
    ("Royal Knights", ["King Drasil", "Omnimon", "Alphamon"], 2),
    ("Royal Knights", ["King Drasil", "Gallantmon", "UlforceVeedramon"], 2),
    ("Royal Knights", ["King Drasil", "Magnamon", "Dynasmon"], 2),
    ("Royal Knights", ["Magnamon", "Omnimon", "Alphamon"], 2),
    ("Royal Knights", ["Magnamon", "Omekamon", "Gallantmon"], 2),
    ("Royal Knights", ["Magnamon", "Omekamon", "Jesmon", "Dynasmon"], 3),
    ("Royal Knights", ["Omekamon", "Jesmon", "Gallantmon", "Dynasmon"], 3),

    # Alphamon (CS variant)
    ("CS Alphamon", ["Alphamon", "Dorumon", "DexDorugoramon"], 2),

    # Chronicle (Alphamon + Ouryumon)
    ("Chronicle", ["Alphamon", "Ouryumon"], 2),
    ("Chronicle", ["Alphamon: Ouryuken", "Ouryumon"], 1),

    # UlforceVeedramon
    ("UlforceVeedramon", ["UlforceVeedramon", "AeroVeedramon"], 2),

    # MagnaGarurumon
    ("MagnaGarurumon", ["MagnaGarurumon", "Lobomon", "KendoGarurumon"], 2),

    # Wargreymon OTK
    ("Wargreymon OTK", ["WarGreymon", "MetalGreymon", "Greymon", "Agumon"], 4),

    # Diaboromon
    ("Diaboromon", ["Diaboromon", "Infermon", "Keramon"], 2),

    # Omnimon variants (CS with Nokia tamer, DNA without)
    ("CS Omnimon", ["Omnimon", "WarGreymon", "MetalGarurumon", "Nokia"], 4),
    ("DNA Omnimon", ["Omnimon", "WarGreymon", "MetalGarurumon"], 3),

    # Numemon
    ("Numemon", ["Numemon", "PlatinumNumemon", "Monzaemon"], 2),

    # Rosemon
    ("Rosemon", ["Rosemon", "Lilamon", "Palmon"], 2),

    # Miragegaogamon
    ("Miragegaogamon", ["MirageGaogamon", "Gaogamon", "Gaomon"], 2),

    # Shinegreymon
    ("Shinegreymon", ["ShineGreymon", "RizeGreymon", "GeoGreymon"], 2),

    # Belphemon
    ("Belphemon", ["Belphemon", "Astamon"], 2),

    # Bloomlordmon (simplified)
    ("Bloomlordmon", ["Bloomlordmon"], 1),

    # Sakuyamon
    ("Sakuyamon", ["Sakuyamon", "Taomon", "Renamon"], 2),

    # Ravemon
    ("Ravemon", ["Ravemon", "Crowmon", "Falcomon"], 2),

    # D-Brigade
    ("D-Brigade", ["Darkdramon", "Commandramon", "Sealsdramon"], 2),

    # Hunters
    ("Hunters", ["Arresterdramon", "Gumdramon"], 2),

    # Justimon
    ("Justimon", ["Justimon", "Cyberdramon"], 2),

    # Leopardmon
    ("Leopardmon", ["Leopardmon", "LoaderLiomon"], 2),
    ("Leopardmon", ["Leopardmon (X Antibody)", "Lillymon"], 2),
    ("Leopardmon", ["Leopardmon (X Antibody)", "Examon"], 2),

    # LordKnightmon
    ("LordKnightmon", ["LordKnightmon", "Knightmon"], 2),

    # Examon
    ("Examon", ["Examon", "Breakdramon", "Slayerdramon"], 2),
    ("Examon", ["Examon", "Wingdramon", "Coredramon"], 3),
    ("Examon", ["Examon", "Groundramon", "Dracomon"], 3),

    # Kentaurosmon
    ("Kentaurosmon", ["Kentaurosmon", "Sleipmon"], 1),

    # Gammamon
    ("Gammamon", ["Gammamon", "BetelGammamon", "Canoweissmon"], 2),

    # Jellymon
    ("Jellymon", ["Jellymon", "TeslaJellymon"], 2),

    # Diarbbitmon (Angoramon line)
    ("Diarbbitmon", ["Angoramon", "SymbareAngoramon"], 2),

    # Phoenixmon (Biyomon line)
    ("Phoenixmon", ["Phoenixmon", "Garudamon", "Birdramon", "Biyomon"], 3),

    # Wind Guardians / Accel (includes Valdurmon)
    ("Wind Guardians", ["Valdurmon", "Harpymon", "Aquilamon"], 2),

    # Deep Savers (aquatic)
    ("Deep Savers", ["Plesiomon", "MarineAngemon", "Gomamon"], 2),
    ("Deep Savers", ["Sangomon", "Shellmon", "MarineBullmon"], 2),
    ("Deep Savers", ["Ryugumon", "Sangomon", "MetalSeadramon"], 2),

    # TyrantKabuterimon
    ("TyrantKabuterimon", ["TyrantKabuterimon", "MegaKabuterimon", "Kabuterimon", "Tentomon"], 3),

    # Machinedramon (standalone, not Millenniummon)
    ("Machinedramon", ["Machinedramon", "MetalTyrannomon", "Megadramon"], 3),
    ("Machinedramon", ["Machinedramon", "Andromon", "Megadramon"], 3),

    # Gabu Bond (Bond of Friendship)
    ("Gabu Bond", ["Gabumon - Bond of Friendship", "Gabumon"], 2),
    ("Gabu Bond", ["Gabumon - Bond of Friendship", "Garurumon"], 2),

    # Agu Bond (Bond of Courage - NOT WarGreymon)
    ("Agu Bond", ["Agumon - Bond of Courage", "Agumon"], 2),
    ("Agu Bond", ["Agumon - Bond of Courage", "Greymon"], 2),

    # GAS (Garuru Alter-S)
    ("GAS (Garuru Alter-S)", ["Alter-S", "CresGarurumon"], 1),

    # Invisimon (standalone)
    ("Invisimon", ["Invisimon"], 1),

    # Blackwargreymon (expanded)
    ("Blackwargreymon", ["BlackWarGreymon", "Agumon", "Greymon"], 2),
    ("Blackwargreymon", ["BlackWarGreymon", "MetalGreymon"], 2),
    ("Blackwargreymon", ["BlackWarGreymon", "Gaiomon"], 2),

    # Dorbickmon
    ("Dorbickmon Combo", ["Dorbickmon", "NeoVamdemon"], 1),

    # Silphymon
    ("Silphymon", ["Silphymon", "Aquilamon", "Gatomon"], 2),

    # Cherubimon
    ("Cherubimon", ["Cherubimon", "Antylamon", "Lopmon"], 2),

    # Megidramon
    ("Megidramon", ["Megidramon", "WarGrowlmon", "Guilmon"], 3),

    # Olympus XII
    ("Olympus XII", ["Jupitermon", "Junomon", "Apollomon"], 2),
    ("Olympus XII", ["Neptunemon", "Mercurymon"], 2),

    # TS Titans (Ogre/Titamon deck)
    ("TS Titans", ["Titamon", "Ogremon", "Goblimon"], 3),
    ("TS Titans", ["Titamon", "SkullBaluchimon"], 2),

    # Deusmon
    ("Deusmon", ["Deusmon", "Cometmon", "Warudamon"], 2),

    # Ghosts (updated cards)
    ("Ghosts", ["Violent Inboots", "Dullahamon", "Ghostmon"], 2),
    ("Ghosts", ["Violent Inboots", "Necromon", "Ghostmon"], 2),
    ("Ghosts", ["Dullahamon", "Necromon", "Ghostmon"], 2),

    # Abbadomon
    ("Abbadomon", ["Abbadomon", "Negamon"], 1),

    # DarkKnightmon (if not caught by Bagra)
    ("DarkKnightmon", ["DarkKnightmon", "SkullKnightmon", "DeadlyAxemon"], 2),

    # Three Musketeers (updated cards)
    ("Three Musketeers", ["Beelstarmon", "Gundramon"], 2),
    ("Three Musketeers", ["Beelstarmon", "Avengekidmon"], 2),
    ("Three Musketeers", ["Beelstarmon", "Magnakidmon"], 2),

    # Four Great Dragons
    ("Four Great Dragons", ["Azulongmon", "Ebonwumon", "Baihumon", "Zhuqiaomon"], 2),

    # Seven Great Demon Lords
    ("Seven Great Demon Lords", ["Daemon", "Barbamon", "Lilithmon", "Leviamon"], 2),

    # Lilithmon
    ("Lilithmon", ["Lilithmon", "LadyDevimon", "BlackGatomon"], 2),

    # Vortex (Zephagamon / Vortexdramon line)
    ("Vortex", ["Zephagamon", "Pteromon", "Vortexdramon"], 2),
    ("Vortex", ["Zephagamon", "Vortexdramon"], 2),
    ("Vortex", ["Zephagamon", "Zephagamon ACE"], 2),
    ("Vortex", ["Zephagamon ACE", "MedievalGallantmon"], 2),

    # Sistermon Puppets (Sistermon + Gankoomon)
    ("Sistermon Puppets", ["Sistermon Blanc", "Sistermon Ciel", "Gankoomon"], 3),
    ("Sistermon Puppets", ["Sistermon Blanc (Awakened)", "Sistermon Ciel (Awakened)", "Gankoomon"], 2),
    ("Sistermon Puppets", ["Sistermon Blanc", "Gankoomon (X Antibody)"], 2),

    # Argomon
    ("Argomon", ["Argomon", "Woodmon", "Mushroomon"], 2),

    # HeavyLeomon
    ("HeavyLeomon", ["HeavyLeomon", "BanchoLeomon", "Leomon"], 2),

    # Rapidmon
    ("Rapidmon", ["Rapidmon", "Gargomon", "Terriermon"], 2),

    # Dinomon (includes Ryutaro Williams tamer)
    ("Dinomon", ["Dinomon", "Agumon", "Ryutaro Williams"], 2),
    ("Dinomon", ["Dinomon", "Ryutaro Williams"], 2),
    ("Dinomon", ["Dinorexmon", "Dinomon", "Agumon"], 2),

    # Red Hybrid (Takuya line) — split by mega
    ("Red Hybrid EmperorGreymon", ["EmperorGreymon", "Aldamon", "BurningGreymon"], 2),
    ("Red Hybrid EmperorGreymon", ["EmperorGreymon", "Agunimon", "Flamemon"], 2),
    ("Red Hybrid AncientGreymon", ["AncientGreymon", "Aldamon", "BurningGreymon"], 2),
    ("Red Hybrid AncientGreymon", ["AncientGreymon", "Agunimon", "Flamemon"], 2),

    # Ariemon
    ("Ariemon", ["Ariemon", "Huankunmon", "Sanzomon"], 2),
    ("Ariemon", ["Ariemon", "Xiangpengmon"], 2),

    # Dynasmon
    ("Dynasmon", ["Dynasmon", "Lordomon"], 1),
    ("Dynasmon", ["Dynasmon (X Antibody)", "Lordomon"], 1),

    # Blue Hybrid (Koji line)
    ("Blue Hybrid", ["MagnaGarurumon", "KendoGarurumon", "Lobomon"], 2),

    # Nightmare Soldiers (Wizardmon / Witchmon variants)
    ("Nightmare Soldiers", ["Wizardmon", "Candlemon", "Witchmon"], 2),
    ("Nightmare Soldiers", ["Wizardmon (X Antibody)", "Wizardmon", "Candlemon"], 2),

    # Appmon (generic - should be last among Appmon rules)
    ("Appmon", ["Dokamon", "Consulmon", "Beautymon"], 2),
    ("Appmon", ["Dokamon", "Coachmon", "Coordemon"], 2),
    ("Appmon", ["Flickmon", "Dokamon", "Oujamon"], 2),
]


def extract_card_names(decklist_json):
    """Extract all card names from a decklist JSON."""
    try:
        decklist = json.loads(decklist_json)
        cards = []
        for category in ['digimon', 'tamer', 'option', 'egg']:
            for card in decklist.get(category, []):
                name = card.get('name', '')
                count = card.get('count', 1)
                # Add card name multiple times based on count for weighted matching
                cards.extend([name] * count)
        return cards
    except:
        return []


def classify_decklist(decklist_json):
    """Classify a decklist based on signature cards. Returns archetype name or None."""
    cards = extract_card_names(decklist_json)
    if not cards:
        return None

    # Create a set of card names for faster lookup (case-insensitive)
    card_set = set(c.lower() for c in cards)
    card_text = ' '.join(cards).lower()

    for archetype_name, required_cards, min_matches in CLASSIFICATION_RULES:
        matches = 0
        for req_card in required_cards:
            # Check if any card contains the required card name (substring match)
            if req_card.lower() in card_text:
                matches += 1

        if matches >= min_matches:
            return archetype_name

    return None


def main():
    parser = argparse.ArgumentParser(description='Auto-classify UNKNOWN decklists')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without applying')
    parser.add_argument('--online-only', action='store_true', default=True, help='Only process online tournaments')
    args = parser.parse_args()

    # Connect to database
    print("Connecting to Neon PostgreSQL...", end=" ", flush=True)
    try:
        conn = get_connection()
        cursor = conn.cursor()
        print("OK")
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)

    # Get archetype name to ID mapping
    cursor.execute('SELECT archetype_id, archetype_name FROM deck_archetypes')
    archetypes = cursor.fetchall()
    archetype_map = {name: id for id, name in archetypes}

    # Get UNKNOWN decklist results
    if args.online_only:
        cursor.execute('''
            SELECT r.result_id, r.decklist_json
            FROM results r
            JOIN tournaments t ON r.tournament_id = t.tournament_id
            JOIN stores s ON t.store_id = s.store_id
            JOIN deck_archetypes d ON r.archetype_id = d.archetype_id
            WHERE s.is_online = TRUE
              AND d.archetype_name = 'UNKNOWN'
              AND r.decklist_json IS NOT NULL
              AND r.decklist_json != ''
        ''')
    else:
        cursor.execute('''
            SELECT r.result_id, r.decklist_json
            FROM results r
            JOIN deck_archetypes d ON r.archetype_id = d.archetype_id
            WHERE d.archetype_name = 'UNKNOWN'
              AND r.decklist_json IS NOT NULL
              AND r.decklist_json != ''
        ''')

    results = cursor.fetchall()
    print(f"Found {len(results)} UNKNOWN results with decklists")
    print()

    # Classify each decklist
    classifications = Counter()
    updates = []

    for result_id, decklist_json in results:
        archetype_name = classify_decklist(decklist_json)
        if archetype_name:
            archetype_id = archetype_map.get(archetype_name)
            if archetype_id:
                classifications[archetype_name] += 1
                updates.append((archetype_id, result_id))
            else:
                print(f"WARNING: Archetype '{archetype_name}' not found in database")

    # Print summary
    print("Classification Results:")
    print("=" * 50)
    for archetype, count in classifications.most_common():
        print(f"  {archetype:<30} {count:>5}")
    print("-" * 50)
    print(f"  {'Total classified':<30} {len(updates):>5}")
    print(f"  {'Remaining UNKNOWN':<30} {len(results) - len(updates):>5}")
    print()

    if args.dry_run:
        print("DRY RUN - No changes applied")
    else:
        # Apply updates
        print(f"Applying {len(updates)} archetype updates...")
        for archetype_id, result_id in updates:
            cursor.execute(
                "UPDATE results SET archetype_id = %s WHERE result_id = %s",
                (archetype_id, result_id)
            )
        conn.commit()
        print("Done!")

    cursor.close()
    conn.close()


if __name__ == '__main__':
    main()
