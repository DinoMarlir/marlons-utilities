package com.github.dinomarlir.marlonsutilities

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import org.bukkit.Bukkit
import org.bukkit.Location

class LocationSerializer: KSerializer<Location> {

    override val descriptor: SerialDescriptor = LocationSurrogate.serializer().descriptor

    override fun serialize(encoder: Encoder, value: Location) {
        val surrogate = LocationSurrogate(value.world.name, value.x, value.y, value.z, value.yaw, value.pitch)
        encoder.encodeSerializableValue(LocationSurrogate.serializer(), surrogate)
    }

    override fun deserialize(decoder: Decoder): Location {
        val surrogate = decoder.decodeSerializableValue(LocationSurrogate.serializer())
        return Location(Bukkit.getWorld(surrogate.worldName), surrogate.x, surrogate.y, surrogate.z, surrogate.yaw, surrogate.pitch)
    }

    @Serializable
    private class LocationSurrogate(val worldName: String, val x: Double, val y: Double, val z: Double, val yaw: Float, val pitch: Float)
}