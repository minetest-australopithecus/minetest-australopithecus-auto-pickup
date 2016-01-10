--[[
Copyright (c) 2015, Robert 'Bobby' Zenz
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]


--- A system which allows to automatically pickup items which are on the ground.
autopickup = {
	--- If the system should be automatically activated.
	activate_automatically = settings.get_bool("autopickup_activate", true),
	
	--- If the system is active/has been activated.
	active = false,
	
	--- The acceleration that is used when the item enters the attraction
	-- radius, defaults to "2, 0, 2".
	attraction_acceleration = settings.get_pos3d("autopickup_attraction_acceleration", { x = 2, y = 0, z = 2 }),
	
	--- The radius within which items are moved towards the player, defaults
	-- to 1.5.
	attraction_radius = settings.get_number("autopickup_attraction_radius", 1.5),
	
	--- The minimum age (in seconds) before dropped items can be picked up
	-- automatically again by the same player, defaults to 4.
	dropped_min_age = settings.get_number("autopickup_dropped_min_age", 4),
	
	--- The interval (in seconds) in which the system is running, defaults
	-- to 0.1.
	interval = settings.get_number("autopickup_interval", 0.1),
	
	--- The radius within which items are picked up, defaults to 0.9.
	pickup_radius = settings.get_number("autopickup_pickup_radius", 0.9),
	
	--- If the sound should be played, defaults to true.
	sound_enabled = settings.get_bool("autopickup_sound_enabled", true),
	
	--- The gain of the sound played, defaults to 0.5.
	sound_gain = settings.get_number("autopickup_sound_gain", 0.5),
	
	--- If the sound be played globally, defaults to true.
	sound_global = settings.get_bool("autopickup_sound_global", true),
	
	--- If the global playing is set, this defines the hearing distance,
	-- defaults to 8.
	sound_hear_distance = settings.get_number("autopickup_sound_hear_distance", 8),
	
	--- The name of the sound to play, defaults to "autopickup".
	sound_name = settings.get_string("autopickup_sound_name", "autopickup")
}


--- Activates the system, if it has not been disabled by setting
-- "autopickup_activate" to false in the configuration.
function autopickup.activate()
	if autopickup.activate_automatically then
		autopickup.activate_internal()
	end
end

--- Activates the system, without checking the configuration. Multiple calls
-- to this function have no effect.
function autopickup.activate_internal()
	if not autopickup.active then
		scheduler.schedule(
			"autopickup",
			autopickup.interval,
			autopickup.pickup_items_all,
			scheduler.OVERSHOOT_POLICY_RUN_ONCE)
		
		autopickup.active = true
	end
end

--- Checks if the given entity has already been collected.
--
-- @param entity The LuaEntity to check.
-- @return true if the entity has already been collected.
function autopickup.has_been_collected(entity)
	return entity.autopickup_collected == nil
end

--- Checks if the given entity has just been dropped by the given player within
-- the configured time.
--
-- @param entity The LuaEntity to check.
-- @param player The Player object.
-- @return true if the given entity has just been dropped by the given player.
function autopickup.has_just_been_dropped_by(entity, player)
	return entity.dropped_by == player:get_player_name()
		and entity.age <= autopickup.dropped_min_age
end

--- Checks if the given entity has a timeout field set and if it is old enough
-- to be picked up automatically.
--
-- @param entity The LuaEntity to check.
-- @return true if the given entity can be picked up automatically.
function autopickup.has_timedout(entity)
	return entity.autopickup_timeout == nil
		or entity.age >= entity.autopickup_timeout
end

--- Checks if the given entity should be picked up automatically or not.
--
-- @param entity The LuaEntity to check.
-- @return true if the given entity should be picked up automatically.
function autopickup.is_allowed(entity)
	return entity.autopickup_disable ~= true
end

--- Checks if the given entity can be automatically picked up.
--
-- @param entity The LuaEntity to check.
-- @param player The Player which would like to pick it up.
-- @return true if the entity can be automatically picked up.
function autopickup.is_autopickupable(entity, player)
	return autopickup.has_been_collected(entity)
		and autopickup.is_allowed(entity)
		and autopickup.has_timedout(entity)
		and not autopickup.has_just_been_dropped_by(entity, player)
end

--- Moves the given object towards the given location with the given velocity.
--
-- @param object The object to move.
-- @param target_pos The target position.
function autopickup.move_towards(object, target_pos)
	entityutil.move_to(
		object,
		target_pos,
		autopickup.attraction_acceleration.x,
		autopickup.attraction_acceleration.y,
		autopickup.attraction_acceleration.z)
end

--- Processes all items in the vicinity of the given player.
--
-- @param player The player object.
function autopickup.pickup_items(player)
	if objectrefutil.is_alive(player) then
		local target_pos = player:getpos()
		local target_inventory = player:get_inventory()
		
		for index, object in ipairs(minetest.get_objects_inside_radius(target_pos, autopickup.attraction_radius)) do
			if entityutil.is_builtin_item(object) then
				local entity = object:get_luaentity()
				
				if autopickup.is_autopickupable(entity, player) then
					local stack = ItemStack(entity.itemstring)
					
					if target_inventory:room_for_item("main", stack) then
						local distance = mathutil.distance2d(target_pos, object:getpos())
						
						if distance <= autopickup.pickup_radius then
							log.verbose(player:get_player_name(), " picks up ", entity.itemstring)
							
							autopickup.play_sound(target_pos, player)
							
						target_inventory:add_item("main", stack)
							
							-- Set a property on the entity so that we don't
							-- collect it a second time.
							entity.autopickup_collected = true
							-- Let's also remove the itemstring to make sure that
							-- this item cannot be picked up anymore.
							entity.itemstring = ""
							object:remove()
						else
							autopickup.move_towards(object, target_pos)
						end
					end
				end
			end
		end
	end
end

--- Processes all players and picks up the items.
function autopickup.pickup_items_all()
	for index, player in ipairs(minetest.get_connected_players()) do
		autopickup.pickup_items(player)
	end
end

--- Plays the configured sound at the given position.
--
-- @param position The position at which to play the sound.
-- @param player The player to who to play the sound, if configured to do so.
function autopickup.play_sound(position, player)
	if autopickup.sound_enabled then
		if autopickup.sound_global then
			minetest.sound_play(autopickup.sound_name, {
				gain = autopickup.sound_gain,
				max_hear_distance = autopickup.sound_hear_distance,
				pos = position
		})
		else
			minetest.sound_play(autopickup.sound_name, {
				gain = autopickup.sound_gain,
				to_player = player:get_player_name()
			})
		end
	end
end

