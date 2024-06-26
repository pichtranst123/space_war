module space_war::game_objects {
    use sui::object::{UID, Self};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::event;
    use space_war::combat_event::{emit_combat_outcome};
    use space_war::combat_rule::{calculate_damage, is_player_winning};
    use space_war::leaderboard::{Leaderboard, update_leaderboard};
    use space_war::ranking::{LeaderboardEntry};
    use space_war::score_event::{emit_score_update};
    use space_war::resource_rule::{calculate_gold_reward};

    // Constants
    const INITIAL_PLAYER_LEVEL: u64 = 1;
    const INITIAL_GOLD: u64 = 0;
    const INITIAL_FIGHTER_HEALTH: u64 = 100;
    const INITIAL_FIGHTER_DAMAGE: u64 = 20;
    const MAX_MISSILES: u64 = 4;
    const MISSILE_DAMAGE: u64 = 50;
    const FIGHTER_UPGRADE_HEALTH: u64 = 30;
    const FIGHTER_UPGRADE_DAMAGE: u64 = 15;
    const PILOT_XP_GAIN: u64 = 10;

    // Admin Cap Structure (admin-only upgrades)
    public struct AdminCap has key {
        id: UID,
    }

    // Owner Cap Structure (ownership permissions)
    public struct OwnerCap has key, store {
        id: UID,
        owner: address,
    }

    // Missile Structure
    public struct Missile has key, store {
        id: UID,
        damage: u64,
    }

    // Space Fighter Structure
    public struct SpaceFighter has key, store {
        id: UID,
        health: u64,
        damage: u64,
        pilot: Option<UID>,
        missiles: vector<Missile>, // Store up to 4 missiles
    }

    // Player Structure
    public struct Player has key, store {
        id: UID,
        address: address,
        level: u64,
        gold: u64,
        fighter: UID, // Links to a Space Fighter
    }

    // Public Functions

    // Create a new Player with Space Fighter, Admin Cap, and Owner Cap
    public entry fun create_player(ctx: &mut TxContext) -> (Player, AdminCap, OwnerCap) {
        // Initialize a new Space Fighter with no missiles
        let fighter = SpaceFighter {
            id: object::new(ctx),
            health: INITIAL_FIGHTER_HEALTH,
            damage: INITIAL_FIGHTER_DAMAGE,
            pilot: option::none(),
            missiles: vector[],
        };

        // Initialize Player, Admin Cap, and Owner Cap
        let player_id = object::new(ctx);
        let address = tx_context::sender(ctx);

        let player = Player {
            id: player_id,
            address,
            level: INITIAL_PLAYER_LEVEL,
            gold: INITIAL_GOLD,
            fighter: fighter.id,
        };

        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        let owner_cap = OwnerCap {
            id: object::new(ctx),
            owner: address,
        };

        (player, admin_cap, owner_cap)
    }

    // Mint a new Missile
    public entry fun mint_missile(ctx: &mut TxContext) -> Missile {
        Missile {
            id: object::new(ctx),
            damage: MISSILE_DAMAGE,
        }
    }

    // Add a missile to the Space Fighter
    public entry fun add_missile_to_fighter(ctx: &mut TxContext, owner_cap: &OwnerCap, fighter: &mut SpaceFighter, missile: Missile) {
        assert!(tx_context::sender(ctx) == owner_cap.owner, "Unauthorized: Only the owner can add missiles");
        assert!(vector::length(&fighter.missiles) < MAX_MISSILES, "Space Fighter already has the maximum number of missiles");

        vector::push_back(&mut fighter.missiles, missile);
    }

    // Upgrade Space Fighter attributes using Admin Cap
    public entry fun upgrade_space_fighter(ctx: &mut TxContext, admin_cap: &AdminCap, fighter: &mut SpaceFighter, player: &mut Player) {
        assert!(admin_cap.id != UID::default(), "Invalid admin cap");
        assert!(player.gold >= FIGHTER_UPGRADE_HEALTH, "Not enough gold for fighter upgrade");

        // Deduct gold
        player.gold -= FIGHTER_UPGRADE_HEALTH;

        // Upgrade health and damage
        fighter.health += FIGHTER_UPGRADE_HEALTH;
        fighter.damage += FIGHTER_UPGRADE_DAMAGE;

        event::emit(UpgradeFighterEvent {
            fighter_id: fighter.id,
            new_health: fighter.health,
            new_damage: fighter.damage,
        });
    }

    // Event Structure for Fighter Upgrade
    struct UpgradeFighterEvent has copy, drop {
        fighter_id: UID,
        new_health: u64,
        new_damage: u64,
    }

}

    #[test_only]
module space_war::game_objects_tests {
    use space_war::game_objects::{Self, create_player, mint_missile, add_missile_to_fighter, upgrade_space_fighter};
    use sui::test_scenario::{Self, Scenario};
    use space_war::space_fighter::{SpaceFighter};

    #[test]
    fun test_create_player_and_missiles() {
        let mut scenario_val = test_scenario::begin(@0x1);
        let scenario = &mut scenario_val;

        // Create player and caps
        let (player, admin_cap, owner_cap) = create_player(scenario);

        // Mint a missile and add to the fighter
        let missile = mint_missile(scenario);
        let mut fighter = test_scenario::take_from_sender<SpaceFighter>(scenario);

        add_missile_to_fighter(scenario, &owner_cap, &mut fighter, missile);
        assert!(vector::length(&fighter.missiles) == 1, "Failed to add missile");

        // Test upgrading space fighter
        upgrade_space_fighter(scenario, &admin_cap, &mut fighter, &mut player);
        assert!(fighter.health > 100, "Space fighter upgrade failed");

        test_scenario::end(scenario_val);
    }
}



    #[test_only]
module space_war::game_flow_tests {
    use space_war::game_objects::{Self, create_player, upgrade_space_fighter, assign_pilot_to_fighter};
    use space_war::combat_rule::{calculate_damage, is_player_winning};
    use sui::test_scenario::{Self, Scenario};
    use space_war::space_fighter::{SpaceFighter};

    #[test]
    fun test_full_gameplay_flow() {
        let mut scenario_val = test_scenario::begin(@0x1);
        let scenario = &mut scenario_val;

        // Create player and caps
        let (player, admin_cap, owner_cap) = create_player(scenario);

        // Mint a pilot and assign to the space fighter
        let pilot_name = "Ace Pilot";
        assign_pilot_to_fighter(scenario, &owner_cap, &mut player, pilot_name);

        // Upgrade the space fighter
        let mut fighter = test_scenario::take_from_sender<SpaceFighter>(scenario);
        upgrade_space_fighter(scenario, &admin_cap, &mut fighter, &mut player);

        // Test combat logic against a monster (basic example)
        let player_damage = calculate_damage(player.level, 20);
        let monster_health = 80;
        assert!(is_player_winning(player_damage, monster_health), "Player should win this fight");

        test_scenario::end(scenario_val);
    }
}