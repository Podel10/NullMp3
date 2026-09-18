package com.nullmp3.nullmp3

import java.io.ByteArrayOutputStream

/// GIF89a writer with one adaptive palette shared by every frame. Doing this in
/// Kotlin keeps long clips off the Dart isolate, where quantising a couple of
/// hundred frames took minutes.
class GifWriter(private val width: Int, private val height: Int) {
    private val payloads = ArrayList<ByteArray>()
    private val table = ByteArray(768)
    private val palR = IntArray(256)
    private val palG = IntArray(256)
    private val palB = IntArray(256)
    private val indices = ByteArray(width * height)
    // Floyd-Steinberg carries the rounding error into the neighbours, so a
    // gradient breaks into fine noise instead of hard bands.
    private var errThis = IntArray((width + 2) * 3)
    private var errNext = IntArray((width + 2) * 3)
    // Open addressed string table for LZW. A HashMap here would box tens of
    // millions of ints for a long clip.
    private val hashKeys = IntArray(HSIZE)
    private val hashCodes = IntArray(HSIZE)
    private var colors = 1

    val frames: Int get() = payloads.size

    /// [samples] holds packed 0xRRGGBB colours taken from across the clip.
    /// Median cut over them gives a palette that suits the whole animation, so
    /// frames can be written one by one without a second look at the pixels.
    fun buildPalette(samples: IntArray, count: Int) {
        if (count < 2) {
            for (i in 0 until 256) {
                table[i * 3] = i.toByte()
                table[i * 3 + 1] = i.toByte()
                table[i * 3 + 2] = i.toByte()
            }
            colors = 256
            return
        }
        val boxes = ArrayList<IntArray>()
        boxes.add(intArrayOf(0, count))
        while (boxes.size < 256) {
            var pick = -1
            var best = 0L
            var channel = 0
            for (i in boxes.indices) {
                val box = boxes[i]
                if (box[1] - box[0] < 2) continue
                val spread = spreadOf(samples, box[0], box[1])
                val range = spread and 0xFFFF
                // Weighing the spread by how many pixels sit in the box keeps
                // the palette on the colours the clip actually uses instead of
                // spending it on rare outliers.
                val score = range.toLong() * (box[1] - box[0])
                if (score > best) {
                    best = score
                    channel = spread ushr 16
                    pick = i
                }
            }
            if (pick < 0 || best == 0L) break
            val box = boxes[pick]
            sortRange(samples, box[0], box[1], channel)
            val mid = (box[0] + box[1]) / 2
            boxes[pick] = intArrayOf(box[0], mid)
            boxes.add(intArrayOf(mid, box[1]))
        }
        colors = boxes.size
        for (i in boxes.indices) {
            val box = boxes[i]
            var r = 0L
            var g = 0L
            var b = 0L
            for (j in box[0] until box[1]) {
                val color = samples[j]
                r += (color ushr 16) and 0xFF
                g += (color ushr 8) and 0xFF
                b += color and 0xFF
            }
            val n = (box[1] - box[0]).coerceAtLeast(1)
            palR[i] = (r / n).toInt()
            palG[i] = (g / n).toInt()
            palB[i] = (b / n).toInt()
            table[i * 3] = palR[i].toByte()
            table[i * 3 + 1] = palG[i].toByte()
            table[i * 3 + 2] = palB[i].toByte()
        }
    }

    fun addFrame(pixels: IntArray) {
        java.util.Arrays.fill(errThis, 0)
        java.util.Arrays.fill(errNext, 0)
        var row = 0
        for (y in 0 until height) {
            // Alternating direction keeps the error from smearing one way.
            val step = if (y % 2 == 0) 1 else -1
            var x = if (step == 1) 0 else width - 1
            var left = width
            while (left-- > 0) {
                val here = row + x
                val color = pixels[here]
                val slot = (x + 1) * 3
                val r = clamp(((color ushr 16) and 0xFF) + ((errThis[slot] + 8) shr 4))
                val g = clamp(((color ushr 8) and 0xFF) + ((errThis[slot + 1] + 8) shr 4))
                val b = clamp((color and 0xFF) + ((errThis[slot + 2] + 8) shr 4))
                val index = nearest((r shl 16) or (g shl 8) or b)
                indices[here] = index.toByte()
                val er = r - palR[index]
                val eg = g - palG[index]
                val eb = b - palB[index]
                val ahead = (x + step + 1) * 3
                val behind = (x - step + 1) * 3
                spill(errThis, ahead, er * 7, eg * 7, eb * 7)
                spill(errNext, behind, er * 3, eg * 3, eb * 3)
                spill(errNext, slot, er * 5, eg * 5, eb * 5)
                spill(errNext, ahead, er, eg, eb)
                x += step
            }
            row += width
            val spent = errThis
            errThis = errNext
            errNext = spent
            java.util.Arrays.fill(errNext, 0)
        }
        payloads.add(compress(indices))
    }

    private fun spill(row: IntArray, base: Int, r: Int, g: Int, b: Int) {
        row[base] += r
        row[base + 1] += g
        row[base + 2] += b
    }

    private fun clamp(value: Int): Int = if (value < 0) 0 else if (value > 255) 255 else value

    fun finish(delayCs: Int): ByteArray {
        var total = 1024
        for (payload in payloads) total += payload.size + 20
        val out = ByteArrayOutputStream(total)
        out.write("GIF89a".toByteArray(Charsets.US_ASCII))
        short(out, width)
        short(out, height)
        // Global colour table, 256 entries, 8 bits per pixel.
        out.write(0xF7)
        out.write(0)
        out.write(0)
        out.write(table)
        // Netscape extension: loop forever.
        out.write(byteArrayOf(0x21, 0xFF.toByte(), 0x0B))
        out.write("NETSCAPE2.0".toByteArray(Charsets.US_ASCII))
        out.write(byteArrayOf(0x03, 0x01, 0x00, 0x00, 0x00))
        val delay = delayCs.coerceIn(2, 100)
        for (payload in payloads) {
            // Graphic control extension: keep the previous frame on screen.
            out.write(byteArrayOf(0x21, 0xF9.toByte(), 0x04, 0x04))
            short(out, delay)
            out.write(0)
            out.write(0)
            out.write(0x2C)
            short(out, 0)
            short(out, 0)
            short(out, width)
            short(out, height)
            out.write(0)
            out.write(0x08)
            out.write(payload)
        }
        out.write(0x3B)
        return out.toByteArray()
    }

    private fun nearest(color: Int): Int {
        // Dithering adds 1–15 units of error. A coarse cache would snap those
        // steps back onto the same palette index and the bands would return.
        val r = (color ushr 16) and 0xFF
        val g = (color ushr 8) and 0xFF
        val b = color and 0xFF
        var best = 0
        var bestDist = Int.MAX_VALUE
        for (i in 0 until colors) {
            val dr = r - palR[i]
            val dg = g - palG[i]
            val db = b - palB[i]
            val dist = dr * dr + dg * dg + db * db
            if (dist < bestDist) {
                bestDist = dist
                best = i
                if (dist == 0) break
            }
        }
        return best
    }

    private fun compress(pixels: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(pixels.size / 2 + 64)
        val block = ByteArray(255)
        var blockLen = 0
        var bits = 0
        var bitCount = 0
        var codeSize = 9
        var next = 258
        java.util.Arrays.fill(hashKeys, -1)

        fun flushBlock() {
            if (blockLen == 0) return
            out.write(blockLen)
            out.write(block, 0, blockLen)
            blockLen = 0
        }

        fun emit(code: Int) {
            bits = bits or (code shl bitCount)
            bitCount += codeSize
            while (bitCount >= 8) {
                block[blockLen++] = (bits and 0xFF).toByte()
                if (blockLen == 255) flushBlock()
                bits = bits ushr 8
                bitCount -= 8
            }
        }

        emit(CLEAR)
        var prefix = pixels[0].toInt() and 0xFF
        for (i in 1 until pixels.size) {
            val k = pixels[i].toInt() and 0xFF
            val key = (k shl 12) or prefix
            // Both halves stay under 4096, so the hash never leaves the table.
            var slot = (k shl 4) xor prefix
            var reused = false
            if (hashKeys[slot] == key) {
                prefix = hashCodes[slot]
                reused = true
            } else if (hashKeys[slot] >= 0) {
                val step = if (slot == 0) 1 else HSIZE - slot
                while (true) {
                    slot -= step
                    if (slot < 0) slot += HSIZE
                    if (hashKeys[slot] == key) {
                        prefix = hashCodes[slot]
                        reused = true
                        break
                    }
                    if (hashKeys[slot] < 0) break
                }
            }
            if (reused) continue
            emit(prefix)
            // A decoder learns entries one code behind, so the width has to
            // grow off the code count from before this entry is added.
            if (next > (1 shl codeSize) - 1 && codeSize < 12) codeSize++
            if (next < 4096) {
                hashKeys[slot] = key
                hashCodes[slot] = next
                next++
            } else {
                emit(CLEAR)
                java.util.Arrays.fill(hashKeys, -1)
                next = 258
                codeSize = 9
            }
            prefix = k
        }
        emit(prefix)
        emit(EOI)
        if (bitCount > 0) {
            block[blockLen++] = (bits and 0xFF).toByte()
            if (blockLen == 255) flushBlock()
        }
        flushBlock()
        out.write(0)
        return out.toByteArray()
    }

    /// Widest channel of a sample range, packed as channel in the high half and
    /// its range in the low half.
    private fun spreadOf(samples: IntArray, from: Int, to: Int): Int {
        var minR = 255
        var maxR = 0
        var minG = 255
        var maxG = 0
        var minB = 255
        var maxB = 0
        for (i in from until to) {
            val color = samples[i]
            val r = (color ushr 16) and 0xFF
            val g = (color ushr 8) and 0xFF
            val b = color and 0xFF
            if (r < minR) minR = r
            if (r > maxR) maxR = r
            if (g < minG) minG = g
            if (g > maxG) maxG = g
            if (b < minB) minB = b
            if (b > maxB) maxB = b
        }
        val dr = maxR - minR
        val dg = maxG - minG
        val db = maxB - minB
        return when {
            dr >= dg && dr >= db -> (0 shl 16) or dr
            dg >= db -> (1 shl 16) or dg
            else -> (2 shl 16) or db
        }
    }

    /// Sorts by one channel by moving it into the high byte, sorting the packed
    /// values, then putting the colours back together.
    private fun sortRange(samples: IntArray, from: Int, to: Int, channel: Int) {
        if (channel != 0) {
            for (i in from until to) samples[i] = rotate(samples[i], channel)
        }
        java.util.Arrays.sort(samples, from, to)
        if (channel != 0) {
            for (i in from until to) samples[i] = unrotate(samples[i], channel)
        }
    }

    private fun rotate(color: Int, channel: Int): Int {
        val r = (color ushr 16) and 0xFF
        val g = (color ushr 8) and 0xFF
        val b = color and 0xFF
        return if (channel == 1) (g shl 16) or (r shl 8) or b else (b shl 16) or (r shl 8) or g
    }

    private fun unrotate(value: Int, channel: Int): Int {
        val high = (value ushr 16) and 0xFF
        val mid = (value ushr 8) and 0xFF
        val low = value and 0xFF
        return if (channel == 1) {
            (mid shl 16) or (high shl 8) or low
        } else {
            (mid shl 16) or (low shl 8) or high
        }
    }

    private fun short(out: ByteArrayOutputStream, value: Int) {
        out.write(value and 0xFF)
        out.write((value ushr 8) and 0xFF)
    }

    private companion object {
        const val CLEAR = 256
        const val EOI = 257
        const val HSIZE = 5003
    }
}
