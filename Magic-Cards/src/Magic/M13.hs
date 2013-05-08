{-# LANGUAGE OverloadedStrings #-}

module Magic.M13 where

import Magic
import Magic.IdList (Id)

import Control.Applicative
import Control.Monad (void)
import Data.Boolean ((&&*))
import Data.Label.Pure (get)
import Data.Label.PureM ((=:), asks)
import Data.Monoid ((<>), mconcat)
import qualified Data.Set as Set



-- HELPER FUNCTIONS: CAST SPEED


instantSpeed :: Contextual (View Bool)
instantSpeed rSelf rActivator =
  case rSelf of
    (Hand rp, _) -> return (rp == rActivator)
    _            -> return False

sorcerySpeed :: Contextual (View Bool)
sorcerySpeed rSelf rp = instantSpeed rSelf rp &&* myMainPhase &&* isStackEmpty
  where
    myMainPhase = do
      ap <- asks activePlayer
      as <- asks activeStep
      return (ap == rp && as == MainPhase)



-- HELPER FUNCTIONS: PLAY ABILITIES


-- | Play a nonland, non-aura permanent.
playPermanent :: ManaPool -> ActivatedAbility
playPermanent mc =
  ActivatedAbility
    { available     = \rSelf rActivator -> do
        self <- asks (object rSelf)
        if Flash `elem` get staticKeywordAbilities self
          then instantSpeed rSelf rActivator
          else sorcerySpeed rSelf rActivator
    , manaCost      = mc
    , tapCost       = NoTapCost
    , effect        = playPermanentEffect
    , isManaAbility = False
    }
  where
    playPermanentEffect :: Contextual (Magic ())
    playPermanentEffect rSelf _ = void $
        view (willMoveToStack rSelf (pure resolvePermanent)) >>= executeEffect

    resolvePermanent _source = return ()

playAura :: ManaPool -> ActivatedAbility
playAura mc =
  ActivatedAbility
    { available     = \rSelf rActivator -> do
        self <- asks (object rSelf)
        if Flash `elem` get staticKeywordAbilities self
          then instantSpeed rSelf rActivator
          else sorcerySpeed rSelf rActivator
    , manaCost      = mc
    , tapCost       = NoTapCost
    , effect        = playAuraEffect
    , isManaAbility = False
    }
  where
    playAuraEffect :: Contextual (Magic ())
    playAuraEffect rSelf p = do
      aura <- view (asks (object rSelf))  -- TODO Reevaluate rSelf on the stack?
      let ok i = collectEnchantPredicate aura <$>
                  asks (object (Battlefield, i))
      ts <- askMagicTargets p (target permanent <?> ok)
      let f :: Id -> ObjectRef -> Magic ()
          f i rStackSelf = do
            self <- view (asks (object rStackSelf))
            let self' = self { _attachedTo = Just (Battlefield, i)
                             , _stackItem = Nothing }
            void $ executeEffect (WillMoveObject (Just rStackSelf) Battlefield self')

      void $ view (willMoveToStack rSelf (f <$> ts)) >>= executeEffect

collectEnchantPredicate :: Object -> Object -> Bool
collectEnchantPredicate aura enchanted = gand
  [ hasTypes tys enchanted
  | EnchantPermanent tys <- get staticKeywordAbilities aura ]

stackTargetlessEffect :: ObjectRef -> (ObjectRef -> Magic ()) -> Magic ()
stackTargetlessEffect rSelf item = do
  eff <- view (willMoveToStack rSelf (pure item))
  void $ executeEffect eff

-- | Creates a trigger on the stack under the control of the specified player.
mkTriggerObject :: PlayerRef -> StackItem -> Magic ()
mkTriggerObject p item = do
  t <- tick
  void $ executeEffect $ WillMoveObject Nothing Stack $
    (emptyObject t p) { _stackItem = Just item }



-- HELPER FUNCTIONS: TARGETING


permanentOrPlayer :: Target -> Maybe (Either Id PlayerRef)
permanentOrPlayer (TargetPlayer p) = Just (Right p)
permanentOrPlayer (TargetObject (Battlefield, i)) = Just (Left i)
permanentOrPlayer _ = Nothing

permanent :: Target -> Maybe Id
permanent (TargetObject (Battlefield, i)) = Just i
permanent _ = Nothing

targetCreatureOrPlayer :: TargetList () (Either Id PlayerRef)
targetCreatureOrPlayer = target permanentOrPlayer <?> ok
  where
    ok t = case t of
      Left i  -> hasTypes creatureType <$> asks (object (Battlefield, i))
      Right _ -> return True



-- COMMON ABILITIES


exalted :: TriggeredAbilities
exalted events (Battlefield, _) p = return [ mkTriggerObject p (boostPT r)
    | DidDeclareAttackers p' [r] <- events, p == p' ]
  where
    boostPT :: ObjectRef -> StackItem
    boostPT r = pure $ \_self -> do
      t <- tick
      void $ executeEffect $ Will $ InstallLayeredEffect r $
        TemporaryLayeredEffect
          { temporaryTimestamp = t
          , temporaryDuration  = UntilEndOfTurn
          , temporaryEffect    = LayeredEffect
            { affectedObjects  = affectSelf
            , modifications    = [ModifyPT (return (1, 1))]
            }
          }
exalted _ _ _ = return []



-- WHITE CARDS


ajani'sSunstriker :: Card
ajani'sSunstriker = mkCard $ do
  name  =: Just "Ajani's Sunstriker"
  types =: creatureTypes [Cat, Cleric]
  pt    =: Just (2, 2)
  play  =: Just (playPermanent [Just White, Just White])
  staticKeywordAbilities =: [Lifelink]

angel'sMercy :: Card
angel'sMercy = mkCard $ do
  name =: Just "Angel's Mercy"
  types =: instantType
  play =: Just ActivatedAbility
    { available       = instantSpeed
    , manaCost        = [Nothing, Nothing, Just White, Just White]
    , tapCost         = NoTapCost
    , effect          = \rSelf rActivator -> stackTargetlessEffect rSelf $ \_ ->
      void $ executeEffect (Will (GainLife rActivator 7))
    , isManaAbility = False
    }

angelicBenediction :: Card
angelicBenediction = mkCard $ do
    name =: Just "Angelic Benediction"
    types =: enchantmentType
    play =: Just (playPermanent [Nothing, Nothing, Nothing, Just White])
    triggeredAbilities =: exalted <> tapTrigger
  where
    tapTrigger :: TriggeredAbilities
    tapTrigger events (Battlefield, _) p =
      mconcat [
          do
            p' <- asks (object rAttacker .^ controller)
            if p == p'
              then return [mkTapTriggerObject p]
              else return []
        | DidDeclareAttackers _ [rAttacker] <- events ]
    tapTrigger _ _ _ = return []

    mkTapTriggerObject :: PlayerRef -> Magic ()
    mkTapTriggerObject p = do
        let ok i = hasTypes creatureType <$> asks (object (Battlefield, i))
        ts <- askMagicTargets p (target permanent <?> ok)
        let f :: Id -> ObjectRef -> Magic ()
            f i _source = void $ executeEffect $ Will (TapPermanent i)
        mkTriggerObject p (f <$> ts)

attendedKnight :: Card
attendedKnight = mkCard $ do
    name      =: Just "Attended Knight"
    types     =: creatureTypes [Human, Knight]
    pt        =: Just (2, 2)
    play      =: Just (playPermanent [Nothing, Nothing, Nothing, Just White])
    staticKeywordAbilities =: [FirstStrike]
    triggeredAbilities     =: trigger
  where
    trigger :: TriggeredAbilities
    trigger = onSelfETB $ \_ p -> mkTriggerObject p (mkSoldier p)

    mkSoldier :: PlayerRef -> StackItem
    mkSoldier p = pure $ \_self -> do
      t <- tick
      void $ executeEffect $ mkSoldierEffect t p

mkSoldierEffect :: Timestamp -> PlayerRef -> OneShotEffect
mkSoldierEffect t p = WillMoveObject Nothing Battlefield $
  (emptyObject t p)
    { _name      = Just "Soldier"
    , _colors    = Set.singleton White
    , _types     = creatureTypes [Soldier]
    , _tapStatus = Just Untapped
    , _pt        = Just (1, 1)
    }

avenSquire :: Card
avenSquire = mkCard $ do
  name      =: Just "Aven Squire"
  types     =: creatureTypes [Bird, Soldier]
  pt        =: Just (1, 1)
  play      =: Just (playPermanent [Nothing, Just White])
  staticKeywordAbilities =: [Flying]
  triggeredAbilities     =: exalted

battleflightEagle :: Card
battleflightEagle = mkCard $ do
    name      =: Just "Battleflight Eagle"
    types     =: creatureTypes [Bird]
    pt        =: Just (2, 2)
    play      =: Just (playPermanent [Nothing, Nothing, Nothing, Nothing, Just White])
    staticKeywordAbilities =: [Flying]
    triggeredAbilities     =: onSelfETB createBoostTrigger
  where
    createBoostTrigger :: Contextual (Magic ())
    createBoostTrigger _ p = do
      let ok i = hasTypes creatureType <$> asks (object (Battlefield, i))
      ts <- askMagicTargets p (target permanent <?> ok)
      let f :: Id -> ObjectRef -> Magic ()
          f i _source = do
            t <- tick
            void $ executeEffect $ Will $
              InstallLayeredEffect (Battlefield, i) TemporaryLayeredEffect
                { temporaryTimestamp = t
                , temporaryDuration  = UntilEndOfTurn
                , temporaryEffect    = LayeredEffect
                  { affectedObjects  = affectSelf
                  , modifications    = [ ModifyPT (return (2, 2))
                                       , AddStaticKeywordAbility Flying
                                       ]
                  }
                }
      mkTriggerObject p (f <$> ts)

captainOfTheWatch :: Card
captainOfTheWatch = mkCard $ do
    name      =: Just "Captain of the Watch"
    types     =: creatureTypes [Human, Soldier]
    pt        =: Just (3, 3)
    play      =: Just (playPermanent [Nothing, Nothing, Nothing, Nothing, Just White, Just White])
    staticKeywordAbilities =: [Vigilance]
    layeredEffects         =: [boostSoldiers]
    triggeredAbilities     =: (onSelfETB $ \_ p -> mkTriggerObject p (mkSoldiers p))
  where
    boostSoldiers = LayeredEffect
      { affectedObjects = affectRestOfBattlefield $ \you ->
          isControlledBy you &&* hasTypes (creatureTypes [Soldier])
      , modifications = [ AddStaticKeywordAbility Vigilance
                        , ModifyPT (return (1, 1))]
      }

    mkSoldiers :: PlayerRef -> StackItem
    mkSoldiers p = pure $ \_self -> do
      t <- tick
      void $ executeEffects $ replicate 3 $ mkSoldierEffect t p

captain'sCall :: Card
captain'sCall = mkCard $ do
  name  =: Just "Captain's Call"
  types =: sorceryType
  play  =: Just ActivatedAbility
    { available       = sorcerySpeed
    , manaCost        = [Nothing, Nothing, Nothing, Just White]
    , tapCost         = NoTapCost
    , effect          = \rSelf rActivator -> do
        t <- tick
        stackTargetlessEffect rSelf $
          \_ -> void $ executeEffects $ replicate 3 $ mkSoldierEffect t rActivator
    , isManaAbility = False
    }

divineFavor :: Card
divineFavor = mkCard $ do
    name =: Just "Divine Favor"
    types =: auraType
    staticKeywordAbilities =: [EnchantPermanent creatureType]
    triggeredAbilities =: (onSelfETB $ \_ you -> mkTriggerObject you (gainLifeTrigger you))
    layeredEffects =: [boostEnchanted]
    play =: Just (playAura [Nothing, Just White])
  where
    gainLifeTrigger you = pure $ \_ -> void $
      executeEffect (Will (GainLife you 3))
    boostEnchanted = LayeredEffect
      { affectedObjects = affectAttached
      , modifications = [ModifyPT (return (1, 3))]
      }



-- RED CARDS


fervor :: Card
fervor = mkCard $ do
    name              =: Just "Fervor"
    types             =: enchantmentType
    play              =: Just (playPermanent [Nothing, Nothing, Just Red])
    layeredEffects    =: [grantHaste]
  where
    grantHaste = LayeredEffect
      { affectedObjects = affectBattlefield $ \you ->
          isControlledBy you &&* hasTypes creatureType
      , modifications = [AddStaticKeywordAbility Haste]
      }

searingSpear :: Card
searingSpear = mkCard $ do
    name  =: Just "Searing Spear"
    types =: instantType
    play  =: Just ActivatedAbility
      { available     = instantSpeed
      , manaCost      = [Nothing, Just Red]
      , tapCost       = NoTapCost
      , effect        = searingSpearEffect
      , isManaAbility = False
      }
  where
    searingSpearEffect :: Contextual (Magic ())
    searingSpearEffect rSelf rActivator = do
      ts <- askMagicTargets rActivator targetCreatureOrPlayer
      let f :: Either Id PlayerRef -> ObjectRef -> Magic ()
          f t rStackSelf = do
            self <- view (asks (object rStackSelf))
            void $ executeEffect $ case t of
              Left i  -> Will (DamageObject self i 3 False True)
              Right p -> Will (DamagePlayer self p 3 False True)
      void (view (willMoveToStack rSelf (f <$> ts)) >>= executeEffect)
