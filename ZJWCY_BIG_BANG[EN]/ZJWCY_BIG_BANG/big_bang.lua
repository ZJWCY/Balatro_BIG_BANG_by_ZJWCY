local PURE_FULL_RED = HEX('FF0000')
local PURE_FULL_BLUE = HEX('0000FF')

SMODS.Atlas {
    key = 'ZJWCY_bgb_atlas1',
    path = 'bgb_atlas1.png',
    px = 71,
    py = 95
}

local BGB_FULL_KEY = 'j_ZJWCY_bgb_big_bang'
local BGB_MAX_REPETITION = 4096
local BGB_scoring_card
local BGB_blueprint_idx
local BGB_blueprint_repetitions
SMODS.Joker {
    key = 'big_bang',
    loc_txt = {
        name = 'Big Bang',
        text = {
            'During a single play, each {C:attention}Ace{}, when scoring, causes',
            'every subsequent scoring card of the {C:attention}same suit{}',
            'to trigger an additional {C:attention}N{} times',
            'For every {C:attention}N{} antes, {C:attention}the value of N doubles{}',
            '{C:inactive}(currently N={}{C:attention}#1#{}{C:inactive},{} {C:attention}#2#{}{C:inactive}/#1# antes){}'
        }
    },
    blueprint_compat = true,
    discovered = true,
    config = { extra = {
            N = 1,
            num_passed_antes = 0,
            repetitions = nil
    } },
    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.N, card.ability.extra.num_passed_antes } }
    end,
    rarity = 2,
    atlas = 'ZJWCY_bgb_atlas1',
    pos = { x = 0, y = 0 },
    cost = 6,
    calculate = function(self, card, context)
        local scoring_card = context.other_card
        local scoring_hand = context.scoring_hand

        if context.before and not context.blueprint then -- A new hand is played.
            self.initialize_repetitions(card)
            return
        end

        if
            context.repetition and
            not context.repetition_only and
            context.cardarea == G.play
        then -- Calculate repetitions for the scoring card.
            return self.get_repetitions(card, scoring_card, context)
        end

        if
            context.individual and
            context.cardarea == G.play and
            (scoring_card:get_id() == 14 or scoring_card.base.nominal == 11) and
            not rawequal(scoring_card, scoring_hand[#scoring_hand])
        then -- The Ace card gives retriggerings to later cards.
            return self.on_ace_scored(card, scoring_card, context)
        end

        if
            context.end_of_round and
            not context.repetition and
            not context.individual and
            not context.blueprint
        then -- The round is passed.
            BGB_scoring_card = nil
            if G.GAME.blind.boss then -- The passed round was a boss blind.
                return self.on_ante_passed(card)
            end
            return
        end
    end,

    initialize_repetitions = function(card)
        card.ability.extra.repetitions = {
            Spades = 0,
            Hearts = 0,
            Clubs = 0,
            Diamonds = 0
        }
        BGB_blueprint_repetitions = {}
    end,

    get_repetitions = function(card, scoring_card, context)
        local repetitions
        if context.blueprint then
            if not rawequal(BGB_scoring_card, scoring_card) then
                BGB_scoring_card = scoring_card
                BGB_blueprint_idx = 1
            end
            if #BGB_blueprint_repetitions < BGB_blueprint_idx then
                BGB_blueprint_repetitions[BGB_blueprint_idx] = {
                    Spades = 0,
                    Hearts = 0,
                    Clubs = 0,
                    Diamonds = 0
                }
            end
            repetitions = BGB_blueprint_repetitions[BGB_blueprint_idx]
            BGB_blueprint_idx = BGB_blueprint_idx + 1
        else
            repetitions = card.ability.extra.repetitions
        end
        return {
            message = localize('k_again_ex'),
            repetitions = repetitions[scoring_card.base.suit],
            card = card
        }
    end,

    on_ace_scored = function(card, scoring_card, context)
        local repetitions
        if context.blueprint then
            if BGB_blueprint_idx > #BGB_blueprint_repetitions then
                BGB_blueprint_idx = 1
            end
            repetitions = BGB_blueprint_repetitions[BGB_blueprint_idx]
            BGB_blueprint_idx = BGB_blueprint_idx + 1
        else
            repetitions = card.ability.extra.repetitions
        end
        for k, v in pairs(repetitions) do
            if scoring_card:is_suit(k) and v < BGB_MAX_REPETITION then
                repetitions[k] = v + card.ability.extra.N
            end
        end
        return {
            message = 'Fusion!',
            colour = G.C.SUITS[scoring_card.base.suit],
            card = card
        }
    end,

    on_ante_passed = function(card)
        local N = card.ability.extra.N
        local num_passed_antes = card.ability.extra.num_passed_antes + 1

        if num_passed_antes < N then
            card.ability.extra.num_passed_antes = num_passed_antes
        else
            card.ability.extra.N = N * 2
            card.ability.extra.num_passed_antes = 0
            return {
                message = 'Inflation!',
                colour = PURE_FULL_RED
            }
        end
    end
}

local CLP_FULL_KEY = 'j_ZJWCY_bgb_collapse'
local CLP_before_count = 1
local CLP_temp_nominals = {}
SMODS.Joker {
    key = 'collapse',
    loc_txt = {
        name = 'Collapse',
        text = {
            "Each card's rank is {C:red}decreased by 1{}",
            'before getting scored, except for {C:attention}Aces{}',
            'At the end of the round, if during the round',
            'no {C:attention}Ace{} card has been {C:attention}played, discarded, or scored{},',
            'upgrade the level of every poker hand {C:attention}played{} in the round'
        }
    },
    blueprint_compat = true,
    discovered = true,
    rarity = 2,
    atlas = 'ZJWCY_bgb_atlas1',
    pos = { x = 1, y = 0 },
    cost = 6,
    calculate = function(self, card, context)
        local interround_info = self.set_interround_info(nil, nil, nil)
        local scoring_hand = context.scoring_hand
        local rank

        if context.before then -- Decrease the rank of non-Ace cards by 1.
            local cards_to_change = self.get_cards_to_change(scoring_hand)

            CLP_before_count = CLP_before_count + 1
            if interround_info.is_to_reset then
                self.set_interround_info(false, false, {})
            end
            if #cards_to_change > 0 then
                self.set_temp_nominals(cards_to_change)
                self:set_bases(cards_to_change)
                return {
                    message = 'Collapse!',
                    colour = PURE_FULL_RED,
                    card = card
                }
            end
            return
        end

        if
            context.repetition and
            not context.blueprint and
            context.cardarea == G.play
        then -- Correct the displayed chips of cards changed when context.before.
            self.set_original_nominals(scoring_hand)
            return
        end

        if
            context.pre_discard and
            not context.blueprint and
            self.ace_idx_in(G.hand.highlighted) > 0
        then -- Check if any Ace is discarded.
            self.set_interround_info(false, true, {})
        end

        if
            context.after and
            not context.blueprint and
            CLP_before_count > 1
        then -- Reset joker-global variables and check if any Ace was played.
            CLP_before_count = 1
            CLP_temp_nominals = {}
            if self.ace_idx_in(context.full_hand) > 0 then
                self.set_interround_info(nil, true, nil)
            else
                interround_info.hands_to_upgrade[(G.FUNCS.get_poker_hand_info(scoring_hand))] = true
            end
            return
        end

        if
            context.end_of_round and
            not context.repetition and
            not context.individual
        then -- Upgrade poker hands played in this round if no Ace has been played, discarded, or scored.
            self.try_upgrade_hands(card, interround_info)
            self.set_interround_info(true, nil, nil)
            return
        end
    end,

    set_interround_info = function(is_to_reset, is_ace_touched, hands_to_upgrade)
        if G.GAME.current_round[CLP_FULL_KEY] == nil then
            G.GAME.current_round[CLP_FULL_KEY] = {
                is_to_reset = false,
                is_ace_touched = false,
                hands_to_upgrade = {}
            }
        end
        local interround_info = G.GAME.current_round[CLP_FULL_KEY]

        if is_to_reset ~= nil then
            interround_info.is_to_reset = is_to_reset
        end
        if is_ace_touched ~= nil then
            interround_info.is_ace_touched = is_ace_touched
        end
        if hands_to_upgrade ~= nil then
            interround_info.hands_to_upgrade = hands_to_upgrade
        end
        return interround_info
    end,

    get_cards_to_change = function(scoring_hand)
        local rank
        local cards_to_change = {}

        for _, v in ipairs(scoring_hand) do
            rank = v:get_id()
            if
                rank < 14 and rank > 0 and
                rank > CLP_before_count and
                not v.debuff
            then
                cards_to_change[#cards_to_change + 1] = v
            end
        end
        return cards_to_change
    end,

    set_temp_nominals = function(cards_to_set)
        local card_to_set
        local rank
        local temp_nominal
        for i = 1, #cards_to_set do
            card_to_set = cards_to_set[i]
            rank = card_to_set.base.id
            if CLP_temp_nominals[rank] == nil then
                CLP_temp_nominals[rank] = {card_to_set, rank - 1}
            elseif rawequal(card_to_set, CLP_temp_nominals[rank][1]) then
                CLP_temp_nominals[rank][2] = CLP_temp_nominals[rank][2] - 1
            end
            temp_nominal = CLP_temp_nominals[rank][2]
            if temp_nominal > 10 then
                card_to_set.base.nominal = 10
            elseif temp_nominal == 1 then
                card_to_set.base.nominal = 11
            else
                card_to_set.base.nominal = temp_nominal
            end
        end
    end,

    set_bases = function(self, cards_to_change)
        local rank
        local sound_percent
        G.E_MANAGER:add_event(Event({trigger = 'immediate', blocking = false, func = function()
            for i, v in ipairs(cards_to_change) do
                G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.1, func = function()
                    rank = tostring(v.base.id - 1)
                    if rank == '12' then rank = 'Q'
                    elseif rank == '11' then rank = 'J'
                    elseif rank == '10' then rank = 'T'
                    elseif rank == '1' then
                        rank = 'A'
                        self.set_interround_info(nil, true, nil)
                    end
                    sound_percent = 0.85 + (i - 0.999) / (#cards_to_change - 0.998) * 0.3
                    play_sound('card1', sound_percent)
                    v:juice_up()
                    v:set_base(G.P_CARDS[string.sub(v.base.suit, 1, 1)..'_'..rank])
                    return true
                end}), 'other')
            end
            return true
        end}))
    end,

    set_original_nominals = function(cards_to_set)
        local rank
        for _, v in ipairs(cards_to_set) do
            G.E_MANAGER:add_event(Event({trigger = 'immediate', blocking = false, no_delete = true, func = function()
                rank = v.base.id
                if rank < 14 and rank > 0 then
                    v.base.nominal = rank > 10 and 10 or rank
                end
                return true
            end}), 'other')
        end
    end,

    ace_idx_in = function(cards)
        for i, v in ipairs(cards) do
            if v:get_id() == 14 then
                return i
            end
        end
        return 0
    end,

    try_upgrade_hands = function(card, interround_info)
        if not interround_info.is_ace_touched then
            card_eval_status_text(card, 'extra', nil, nil, nil, {message = 'Blueshift!', colour = PURE_FULL_BLUE})
            for k in pairs(interround_info.hands_to_upgrade) do
                update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize(k, 'poker_hands'),chips = G.GAME.hands[k].chips, mult = G.GAME.hands[k].mult, level=G.GAME.hands[k].level})
                level_up_hand(card, k, nil, 1)
                update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
            end
        end
    end
}

SMODS.Challenge {
    key = 'big_bang_challenge',
    loc_txt = {
        name = 'BIG BANG'
    },
    jokers = {
        { id = 'j_dna', edition = 'negative'},
        { id = BGB_FULL_KEY, eternal = true },
        { id = CLP_FULL_KEY, eternal = true }
    },
    deck = {
        type = 'Challenge Deck',
        cards = {
            {s='C',r='A',e='m_glass',g='Red'},{s='C',r='A',e='m_glass',g='Red'},{s='C',r='A',e='m_glass',g='Red'},
            {s='C',r='A',e='m_glass',g='Red'},{s='C',r='A',e='m_glass',g='Red'},

            {s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},
            {s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},
            {s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},{s='C',r='3',e='m_glass',g='Red'},
            {s='C',r='3',e='m_glass',g='Red'},
            {s='C',r='3',g='Red'},{s='C',r='3',g='Red'},{s='C',r='3',g='Red'},{s='C',r='3',g='Red'},{s='C',r='3',g='Red'},

            {s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},
            {s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},
            {s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},{s='C',r='K',e='m_glass',g='Red'},
            {s='C',r='K',e='m_glass',g='Red'},
            {s='C',r='K',g='Red'},{s='C',r='K',g='Red'},{s='C',r='K',g='Red'},{s='C',r='K',g='Red'},{s='C',r='K',g='Red'}
        }
    }
}
