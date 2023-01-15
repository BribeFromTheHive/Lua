OnInit("ArcingTextTag", function()

    local timed = Require.strict "Timed" --https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/

-- Arcing Text Tag Lua v1.0, created by Maker, converted by Bribe, features requested by Ugabunda and Kusanagi Kuro
-- 
--   public static ArcingTextTag lastCreated
--   - Get the last created ArcingTextTag
--   public number scaling
--   - Set the size ratio of the texttag - 1.00 is the default
--   public number timeScaling
--   - Set the duration ratio of the texttag - 1.00 is the default

    local SIZE_MIN        = 0.018         ---@type number   -- Minimum size of text
    local SIZE_BONUS      = 0.012         ---@type number   -- Text size increase
    local TIME_LIFE       = 1.0           ---@type number   -- How long the text lasts
    local TIME_FADE       = 0.8           ---@type number   -- When does the text start to fade
    local Z_OFFSET        = 50            ---@type number   -- Height above unit
    local Z_OFFSET_BON    = 50            ---@type number   -- How much extra height the text gains
    local VELOCITY        = 2             ---@type number   -- How fast the text moves in x/y plane
    local ANGLE           = math.pi*0.50  ---@type number   -- Movement angle of the tex                                    -- ANGLE_RND is true
    local ANGLE_RND       = true          ---@type boolean  -- Is the angle random or fixed
    
    ArcingTextTag = {}
    
    local math = math

    ---@param s string
    ---@param u unit
    ---@param duration? number
    ---@param size? number
    ---@param p? player
    ---@return texttag
    function ArcingTextTag.create(s, u, duration, size, p)
        duration    = duration  or TIME_LIFE
        size        = size      or 1
        p           = p         or GetLocalPlayer()

        local a = ANGLE_RND and GetRandomReal(0, 2*math.pi) or ANGLE
        
        local scale = size
        local timeScale = math.max(duration, 0.001)
        
        local x = GetUnitX(u)
        local y = GetUnitY(u)
        local t = TIME_LIFE*timeScale
        local as = math.sin(a)*VELOCITY
        local ac = math.cos(a)*VELOCITY
        
        local tt
        if IsUnitVisible(u, p) then
            tt = CreateTextTag()
            SetTextTagPermanent(tt, false)
            SetTextTagLifespan(tt, t)
            SetTextTagFadepoint(tt, TIME_FADE*timeScale)
            SetTextTagText(tt, s, SIZE_MIN*size)
            SetTextTagPos(tt, x, y, Z_OFFSET)
        end
        timed.echo(0.03125, t, function(elapsed)
            if tt then
                local delta = math.sin(math.pi*(elapsed / timeScale))
                x = x + ac
                y = y + as
                SetTextTagPos(tt, x, y, Z_OFFSET + Z_OFFSET_BON*delta)
                SetTextTagText(tt, s, (SIZE_MIN + SIZE_BONUS*delta)*scale)
            end
        end)
        ArcingTextTag.lastCreated = tt
        return tt
    end
end, Debug and Debug.getLine())