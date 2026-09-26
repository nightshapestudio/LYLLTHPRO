# LUNATK factory bank

176 presets. Every one is rendered through the engine in a musical phrase and mixed against a reference arrangement, then gated on loudness, headroom, low end, top end, width, mono fold-down, tails, tuning, macro range, MOTION, velocity and CPU (`tools/lunatk_bank/build.py`).

## Macros (every preset)

- **MACRO 1 TONE**: darker below its default, brighter above.
- **MACRO 2 MOTION**: scales all movement; at 0 the sound stands still.
- **MACRO 3 SPACE**: drier below its default, wetter above.
- **MACRO 4 GRIT**: 0 is the designed tone; up adds drive and damage.

## BASS (24)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **RUSTED PISTON** | Folded saw bass that snarls on every note, with a clean sine underneath | E0–E2 | FOREGROUND | Industrial rock, EBM, dark techno, trailer | Driving eighths and held roots | The sub stays clean; if the snarl fights a guitar, cut 800 Hz before you touch GRIT |
| **CORRODE LINE** | Pulse bass crushed before a ladder filter: the grain moves with every eighth | E0–E2 | FOREGROUND | Industrial, darkwave, electro, glitch | Sixteenth and eighth lines | Bit grain lives at 2–5 kHz; a low-pass at 6 kHz on the bus keeps it off the cymbals |
| **BLOWN SPEAKER** | Square bass through a filter feeding back on itself: harder notes break up more | E0–E2 | FOREGROUND | Industrial rock, noise rock, trap, film | Play dynamics: soft notes round, hard notes tear | Velocity drives the feedback; quantize velocity to about 90 for a steady part |
| **GRINDER** | Growl table chewed by a sixteenth-note wavetable sequence locked to the bar | E0–E2 | RHYTHM | Industrial techno, bass music, EBM | Hold notes; the grind is the rhythm | MOTION sets how hard it chews; at 0 it is a steady growl |
| **HOLLOW MOTOR** | A sine rectified into an octave-up buzz: hollow, mechanical, all mid | E0–E2 | SUPPORT | Minimal industrial, film, darkwave | Slow lines and held notes | No real sub harmonics beyond the sine; layer a kick-friendly sub if the track needs weight |
| **WOUND SUB** | A sine sub wrapped in its own harmonics so it reads on laptops and phones | C0–C2 | SUPPORT | Trap, industrial pop, cinematic, techno | Long notes and slides | TONE and velocity add harmonics; the fundamental stays put for the kick to sit on |
| **CHAIN DRAG** | Saw bass with a sample-rate crush that spikes on a syncopated grid | E0–E2 | RHYTHM | Industrial, breakbeat, EBM, horror | Eighths and held roots | The crush spikes land on the song's grid; MOTION 0 leaves a steady, lightly crushed tone |
| **KNIFE REESE** | Detuned saw reese with a tuned comb ringing an octave up | E0–E2 | FOREGROUND | Drum and bass, industrial, dark techno | Long notes; slides between them | The detune is narrow on purpose, so it survives mono. The comb ring sits near 200–400 Hz; dip there if it boxes |
| **DOWNSHIFT** | Saw bass blended with a copy shifted a few hertz down: it beats and sours against itself | E0–E2 | SUPPORT | Film score, dark ambient, industrial | Held notes, slow lines | The beating is the point; for a tighter low end high-pass the shifted copy with TONE down |
| **IRON LUNG** | A breathing, vowel-shaped bass that opens and closes over the bar | E0–E2 | FOREGROUND | Industrial, trip-hop, horror, darkwave | Held notes and slow riffs | The vowel lives at 400–900 Hz; keep vocals out of that band or automate TONE down under them |
| **STATIC PRESSURE** | Acid-style resonant saw with a sixteenth accent pattern locked to the bar | E0–E2 | RHYTHM | Industrial techno, EBM, acid | Hold notes and let the accents play; pattern B is straighter | Resonance peaks move with the accents; a dynamic EQ at 300–600 Hz tames the loudest ones |
| **BENT RAIL** | Square bass that always slides and folds harder as notes hold | E0–E2 | FOREGROUND | Industrial, synthwave, electro, film | Legato lines; every note glides into the next | Glide is always on: quantize note starts so the slides land on time |
| **CONCRETE FM** | FM bass with a hard metallic bark on the attack | E0–E2 | FOREGROUND | Industrial, EBM, techno, game | Short notes; the bark is on every attack | The bark sits at 1–2 kHz; that is where to cut if it covers the snare |
| **VOID PUNCH** | A pitch-dropping punch bass with crackle and crush on the hit | E0–E2 | RHYTHM | Industrial hip-hop, trap, breakbeat | Short notes on the beat; a kick-bass for sparse beats | It fights the kick: pick one to own 50 Hz, or sidechain this to the kick |
| **TAPE SNARL** | Overdriven saw bass that wobbles like a stretched tape | E0–E2 | FOREGROUND | Industrial rock, lo-fi, film, darkwave | Held notes and slow riffs | The wobble is a few cents; pull MOTION down if it rubs against a tuned guitar |
| **WIRE BITE** | Triangle bass with a ring-modulated wire edge an octave up | E0–E2 | FOREGROUND | Industrial, EBM, post-punk | Picked-bass style lines | The wire edge reads through distorted guitars; TONE down if it gets thin |
| **GUT PUNCH** | A long 808-style boom, saturated so the tail growls | C0–C2 | RHYTHM | Industrial hip-hop, trap, cinematic hits | One note per hit; tune it to the song | It is a kick and a bass at once: leave room by thinning the kick below 80 Hz |
| **SEIZURE** | Held bass chopped into stuttering sixteenths on the bar; four patterns | E0–E2 | RHYTHM | Industrial, glitch, breakbeat, trailer | Hold roots; switch patterns with PATTERN or the switch keys | MOTION 0 opens the gate fully for a plain drone; half way is a softer stutter |
| **SLUDGE** | Thick, low, saturated through a feedback loop: slow and heavy | E0–E2 | FOREGROUND | Doom industrial, trailer, noise rock | Slow, heavy notes | A lot of 150–300 Hz: carve that out of guitars, not out of this |
| **METAL TONGUE** | Plucked metal bass: a tuned comb rings on each note | E0–E2 | FOREGROUND | Industrial, darkwave, film, experimental | Plucked eighths and held roots | The ring is tuned to the note, so it stays musical; shorten notes if the rings pile up |
| **RED LINE** | Wall-of-noise bass for choruses: crushed, clipped and bright | E0–E2 | FOREGROUND | Industrial rock, metal, noise, trailer | Driving eighths under guitars | It is loud in the mids by design; give it the chorus and something cleaner for the verse |
| **BLACK SIGNAL** | Talking bass: the vowel glides through four shapes over two bars | E0–E2 | FOREGROUND | Industrial funk, darkwave, electro | Held notes; the vowels move by themselves | MOTION 0 freezes the vowel; TONE picks which one |
| **SIREN FLOOR** | Slow-sweeping sub bass that rises and falls over two bars; mod wheel for vibrato | E0–E2 | SUPPORT | Cinematic, dark ambient, trap | Long held notes | The sweep is slow enough to feel like tension, not wobble; MOTION 0 fixes it |
| **TORN CABLE** | Hard-sync bass that rips on every attack, then settles | E0–E2 | FOREGROUND | Industrial, electro, EBM | Staccato eighths | The rip is fast; if it clicks against the kick, delay the bass a few milliseconds |

## LEAD (18)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **SCREAMING WIRE** | Saw lead through a resonant filter feeding back on itself: it screams as it opens | C3–C5 | FOREGROUND | Industrial rock, noise, trailer, cyberpunk | Held notes and slow melodies; mod wheel for vibrato | The scream lives at 2–4 kHz. Cut there on the guitars, not on this |
| **TORN SIREN** | Hard-sync lead that rips on the attack, with a metal ring an octave up | C3–C5 | FOREGROUND | Industrial, synthwave, electro, game | Short phrases; every note rips | The rip is loud for a moment; a fast compressor on the lead evens it out |
| **GLASS NERVE** | A pure sine that frays: a rectified octave edge and a copy shifted a few hertz off, beating slowly | C4–C6 | FOREGROUND | Film score, ambient, trip-hop, industrial ballads | Slow melodies with space between notes | Uneasy on purpose. MOTION 0 stops the drift; SPACE up for the score version |
| **RUST HORN** | A breathy, rusted brass voice that opens into a vowel as it holds | C3–C5 | FOREGROUND | Industrial, darkwave, cinematic, doom | Slow swells and held melodies | The vowel sits where a singer does: use it instead of a vocal line, or duck it under one |
| **DEAD FREQUENCY** | A lead through a broken radio: band-passed, crushed, with static that jumps in time | C3–C5 | FOREGROUND | Industrial, trip-hop, hip-hop, horror | Short melodic hooks | Band-passed, so it never clouds the lows; push it louder than you think |
| **HOLLOW CRY** | A mournful FM voice with a tuned comb ringing inside it; long glides | C4–C6 | FOREGROUND | Film score, dark ambient, ballads | Slow legato lines; bend is an octave | Long echoes: shorten SPACE when the melody gets busy |
| **MACHINE WHINE** | Square lead ring-modulated a fifth up: a whine with a ghost an octave below | C3–C5 | FOREGROUND | Industrial, EBM, electro | Riffs and hooks | The ring's low ghost can clash with the bass on long notes; keep it above C3 |
| **OVERLOAD** | A wall of driven saws with the octave below: a lead that behaves like a guitar | C3–C5 | FOREGROUND | Industrial rock, metal, trailer | Power-chord style riffs, one note at a time | Pan it opposite a guitar; its narrow width keeps it solid in mono |
| **DEAD CHANNEL** | A whistle made of noise: a comb tuned to the note, singing through static | C4–C6 | FOREGROUND | Dark ambient, film, industrial, experimental | Slow melodies | Airy by nature; a low-pass at 9 kHz keeps it off the hats |
| **SPLIT LIP** | A folded lead whose snarl pulses in a dotted rhythm on the bar | C3–C5 | RHYTHM | Industrial, EBM, cyberpunk | Held notes; the rhythm is built in | Pattern B is straight sixteenths; MOTION 0 is a steady fold |
| **SCAR TISSUE** | A sine driven through a wavefolding sine shaper: bright bell-like attack, purer tail, a little crushed | C3–C5 | FOREGROUND | Industrial pop, film, electro | Melodies with space; velocity sets the brightness | Plays softer than it looks: hit harder for the edge |
| **CATHODE** | A digital lead with stepped, crushed edges that sweep across the bar | C3–C5 | FOREGROUND | Industrial, chiptune-noir, EBM, game | Riffs and arps played by hand | The crush makes 5–8 kHz grain; a shelf down there tames it on headphones |
| **BLEED** | A sliding sync lead; the mod wheel pushes its filter into feedback | C3–C5 | FOREGROUND | Industrial, synthwave, film | Legato lines; wheel up for the climax | Wheel all the way is harsh on purpose: ride it, don't park it there |
| **FILAMENT** | A thin, nasal pulse lead phasing through a feedback filter | C4–C6 | SUPPORT | Industrial, post-punk, darkwave | Counter-melodies over a busy track | Thin on purpose: it sits above everything without taking space |
| **SHATTERED GLIDE** | A saw lead whose shimmering, shifted double drifts in and out of tune with it | C3–C5 | FOREGROUND | Film, industrial ballads, ambient | Slow legato phrases with long glides | The drift is a couple of hertz; MOTION 0 holds the double still |
| **TENSION CABLE** | A slow, bowed metal voice that swells in with a ringing comb an octave up | C3–C5 | FOREGROUND | Film score, horror, ambient | Long notes that swell; let each one bloom | Slow attack: play early, or it lands late |
| **ALARM ROOM** | A square alarm whose tritone ring switches on and off in eighths | C4–C6 | FOREGROUND | Industrial, horror, techno | Short, repeated figures | Dissonant by design: keep it to stabs and hooks, not the main melody |
| **SPINE CRAWL** | A growling lead whose throat crawls through four shapes every half bar | C3–C5 | FOREGROUND | Industrial, bass music, EBM | Held notes; the growl moves in time | Mid-heavy growl: give it the space between vocal phrases |

## PAD (22)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **ASH CATHEDRAL** | A choir with a shifted ghost of itself drifting in and out of tune, in a large hall | C3–C5 | TEXTURE | Film score, dark ambient, industrial ballads | Slow chords, two bars or more | The ghost beats slowly against the choir; MOTION 0 holds it still if a vocal needs a steady bed |
| **NERVE FIELD** | A wide supersaw bed, lightly crushed, opening and closing over two bars on the grid | C3–C5 | SUPPORT | Industrial rock, trailer, synthwave, darkwave | Sustained chords under a band | The crush is 22%: it adds grain, not noise. Start chords on the bar so the sweep lines up |
| **RUSTED HYMN** | An organ played back from a damaged tape: crushed, wavering and trembling | C3–C5 | SUPPORT | Film score, lo-fi, industrial ballads, horror | Hymn-like chords | The wow is a few cents; pull MOTION down against pianos and guitars |
| **SICK LIGHT** | Glass with a faint ring a fifth up and a drifting shifted copy: pretty, and slightly wrong | C3–C5 | TEXTURE | Film score, horror, ambient | Slow chords; long releases | Unsettling in a minor key, sweet in a major one; MOTION rides the wrongness |
| **PRESSURE FRONT** | A swelling analog bed with a resonant filter feeding back as it opens | C3–C5 | SUPPORT | Trailer, industrial, dark techno breakdowns | Chords held for bars; the swell takes 3 seconds | The feedback peak moves over four bars; if it whistles in your key, pull TONE down |
| **BURIED CHOIR** | Voices under the floor: breathy, vowel-shaped, with a hollow comb an octave down | C3–C5 | TEXTURE | Horror, dark ambient, film score, doom | Slow minor chords | Muffled on purpose; TONE up to bring it out of the ground |
| **GHOST STATIC** | A soft pad heard through a worn record: crackle, crush and a slow filter | C3–C5 | SUPPORT | Lo-fi, trip-hop, film, industrial ballads | Chords under vocals | The crackle is on its own layer; MOTION makes it breathe on the beat |
| **FALSE DAWN** | Harmonics climbing for four bars, then falling back: a sunrise that never quite arrives | C3–C5 | TEXTURE | Film score, post-rock, ambient, trailer builds | Chords held through four-bar phrases, starting on the bar | The climb resets every four bars on the song grid; MOTION 0 freezes the colour |
| **COLD ENGINE** | A mechanical pulse-wave bed phasing through a feedback filter | C3–C5 | SUPPORT | Industrial, EBM, darkwave, sci-fi | Held chords; the phasing is the motion | Busy in the mids; leave the snare room around 2 kHz |
| **WET CONCRETE** | Dark, heavy and saturated, in a big wet room | C3–C5 | SUPPORT | Doom, trailer, industrial, drone | Slow chords in the low-mids | Lots of 200–500 Hz: high-pass the guitars, or this, at 150 |
| **THIN ICE** | High glass shimmer with a shifted copy sliding under it | C4–C6 | TEXTURE | Film, ambient, post-rock | Chords high up, over everything else | Sits above 350 Hz; pair it with a dark pad for the body |
| **BROKEN HALO** | An angelic choir half-shifted out of tune: halo and wound in the same sound | C3–C5 | TEXTURE | Film score, industrial ballads, ambient | Slow chords | The shifted half is 45%: turn MIX-heavy tracks' vocals up, not this down |
| **SLOW BLEED** | Detuned saws that drift apart and fold at the edges, over four bars | C3–C5 | SUPPORT | Industrial ballads, synthwave, film | Long chords | The drift is slow and small; MOTION 0 locks the tuning for piano parts |
| **INTERFERENCE** | A pad that glitches in rhythm: the crush spikes on a syncopated sixteenth grid | C3–C5 | RHYTHM | Industrial, glitch, IDM, trailer | Held chords; the glitch is the groove | Pattern B is straight; MOTION 0 leaves a steady, lightly crushed pad |
| **MOTHER TONGUE** | Voices that speak four vowels over four bars | C3–C5 | TEXTURE | Film, darkwave, trip-hop, ambient | Chords that last whole phrases | Vowels move on the bar; TONE shifts which ones, MOTION 0 holds one |
| **SCAR FIELD** | A warm bed whose sine shaper wrinkles and smooths over two bars | C3–C5 | SUPPORT | Industrial ballads, film, synth-pop | Chords under vocals | Warm in the low-mids: works as the main pad in a sparse mix |
| **FERRIC** | A metallic bed with combs ringing an octave up, like struck iron that won't stop | C3–C5 | TEXTURE | Industrial, horror, sci-fi, film | Slow chords; the ring is part of the sound | Rings at the octave, so it stays in key; shorten notes if they smear together |
| **SUBMERSION** | A pad heard from under water: dark, swaying, with a low hiss | C3–C5 | TEXTURE | Dark ambient, film, trip-hop | Slow chords under a sparse arrangement | Very dark: TONE up if it vanishes under other parts |
| **NAKED WIRE** | Sines rectified into a buzzing octave edge that comes and goes | C3–C5 | SUPPORT | Industrial, minimal, film | Chords with space around them | Edgy in the upper mids; a de-esser-style cut at 3 kHz softens it |
| **SIGNAL DECAY** | Each chord starts clean and crumbles as it holds; higher notes crumble more | C3–C5 | TEXTURE | Film score, lo-fi, industrial ballads | Long chords: the decay takes about three seconds | Short chords stay clean; hold them to hear it fall apart |
| **MIDNIGHT ORGAN** | An overdriven organ through a deep chorus, spinning like a rotating speaker | C3–C5 | SUPPORT | Industrial ballads, blues-noir, film | Chords and held voicings | The spin is on MOTION; 0 is a still, driven organ |
| **HOLLOW EARTH** | A low, hollow bed resonating like a cave: the chord played an octave down | C2–C4 | SUPPORT | Doom, trailer, dark ambient | Chords played low | Lives low: high-pass the bass above 100 Hz, or drop this when the bass plays |

## KEYS (16)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **BURNT PIANO** | A piano after a fire: strings ringing through a comb, sample rate a little broken, tuning a little loose | C2–C6 | FOREGROUND | Film score, industrial ballads, dark pop | Sparse chords and single-note lines | The wobble is under 4 cents; MOTION 0 for a steady piano against strings |
| **FELT MEMORY** | A felted, close-miked piano: soft hammers, breathy, intimate | C2–C6 | FOREGROUND | Film score, ambient, singer-songwriter, lo-fi | Soft, slow chords; the breath is the hammer | Very dark: it wants to be up front and quiet, not buried |
| **PRAYER BOX** | A music box played off a warped cassette: tines, crush and a slow wow | C4–C7 | FOREGROUND | Film score, horror, lullaby-noir, lo-fi | Simple high melodies and broken chords | Lives above 300 Hz; the wow is on MOTION |
| **DEAD ROOM RHODES** | An electric piano with a tine bark that growls when you dig in | C2–C6 | FOREGROUND | Industrial ballads, trip-hop, neo-soul noir, film | Chords with dynamics; hit harder for the bark | Tremolo is on MOTION; the bark is on velocity and TONE |
| **SPLINTER CLAV** | A distorted clavinet-style pluck with a woody comb ring | C2–C5 | RHYTHM | Industrial funk, EBM, electro, rock | Short, choppy chords and riffs | Choppy by nature: play it tight on the grid |
| **WIRE HARPSICHORD** | A harpsichord strung with wire and slightly crushed | C2–C6 | FOREGROUND | Gothic, darkwave, film, baroque-noir | Arpeggiated chords by hand, counterpoint | Bright pluck: EQ a little 3 kHz down if it sits on top of a vocal |
| **HOLLOW WURLI** | A reedy electric piano that buzzes when struck hard, with tremolo | C2–C6 | FOREGROUND | Industrial ballads, trip-hop, indie | Chords and riffs with dynamics | Soft playing stays round; the buzz arrives above about velocity 90 |
| **TOY OF GLASS** | A toy piano with a faint inharmonic clang, a little out of tune | C4–C7 | FOREGROUND | Film score, horror, indie, lullaby-noir | Simple, high melodies | Childlike and wrong: great doubling a real piano an octave up |
| **SCORCHED EP** | An electric piano pushed through a failing amp, on warped tape | C2–C6 | FOREGROUND | Industrial rock, trip-hop, lo-fi, film | Chords and simple riffs | Distortion is 40% by default: GRIT down for verses, up for choruses |
| **NIGHT CELESTE** | Celeste bells with a faint shifted shimmer and a little crush | C4–C7 | TEXTURE | Film score, ambient, winter-noir | High chords and arpeggios by hand | Sparkles above 300 Hz: pair with a warm pad below |
| **CRACKED UPRIGHT** | An out-of-tune bar-room upright on a crackling record | C2–C6 | FOREGROUND | Film, lo-fi, blues-noir, industrial ballads | Chords and melodies; the detune is honky-tonk | The 14-cent detune is the character; don't layer it with a tuned piano |
| **ORGAN RUST** | A percussive organ with a rusty rectified edge, spinning | C2–C6 | RHYTHM | Industrial, garage-noir, gothic | Stabs and short chords | The percussive click is on each note; play it staccato |
| **BELL TOWER DUST** | Low FM bells, slightly detuned against each other, dusty | C2–C5 | FOREGROUND | Film score, gothic, ambient, horror | Slow chords; let them ring | Long rings: leave space, or shorten with fewer notes |
| **SHORTWAVE KEYS** | Keys heard on a shortwave radio that won't stay tuned | C3–C6 | TEXTURE | Trip-hop, hip-hop, film, industrial | Chords and loops | Band-passed: it never fights the bass or the air; sample it into a loop |
| **BENT REED** | A reed organ with a failing bellows: breathy, vowel-coloured, wavering | C2–C6 | FOREGROUND | Gothic, folk-noir, film | Held chords and hymns | Wavers a couple of cents; MOTION 0 to steady it |
| **STEEL KEYS** | Metallic keys: steel partials with a ring and a comb an octave up | C2–C6 | FOREGROUND | Industrial, sci-fi, film | Chords and ostinatos | Everything rings at octaves, so it stays in key |

## PLUCK (16)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **RAZOR PLUCK** | A saw pluck with a folded snap on the attack | C3–C6 | RHYTHM | Industrial, EBM, cyberpunk, techno | Sixteenth patterns and riffs | The snap is 120 ms long; it cuts through without adding level |
| **METAL SNAP** | A tuned metal string snapped: comb body with a ring on top | C3–C6 | RHYTHM | Industrial, film, sci-fi, IDM | Arpeggios and ostinatos | Rings at octaves; stays in key under any chord |
| **GLASS SHARD** | A glass pluck, lightly crushed, bouncing in a ping-pong echo | C4–C6 | RHYTHM | Film, ambient, trip-hop, pop-noir | Arpeggios and sparse figures | Echo is 3/16: it plays a counter-rhythm; SPACE down to tighten |
| **CORRODED HARP** | A harp whose strings have rusted: resonant, crushed at the edges | C3–C6 | FOREGROUND | Film score, gothic, ambient, horror | Broken chords and slow arpeggios | Let notes ring; it wants space around it |
| **RUST DROP** | An FM drop that falls into its note, clipped and metallic | C3–C6 | RHYTHM | Industrial, glitch, electro, game | Fast patterns; every note drops in | The drop is 60 ms; it reads as attack, not as a pitch bend |
| **NERVE TICK** | A tiny tuned tick: a burst of noise ringing a comb at the note | C4–C6 | RHYTHM | IDM, industrial, glitch, minimal | Fast sixteenths; it is almost percussion | Tiny on its own; double a bassline with it for articulation |
| **BONE PLUCK** | A hollow wooden mallet: a sine shaped into overtones, knocking a comb | C3–C6 | RHYTHM | Film, ethno-industrial, minimal, IDM | Ostinatos and melodies | Marimba-like but darker; velocity sets the knock |
| **STATIC PLUCK** | Digital static plucked into a tuned string | C3–C6 | RHYTHM | Glitch, IDM, industrial, hip-hop | Arpeggios; each note is a little different | The grain changes every sixteenth on MOTION |
| **BENT KALIMBA** | A thumb piano with bent tines: a faint shifted shimmer and a little wobble | C3–C6 | FOREGROUND | Film, trip-hop, folk-noir, lullaby-noir | Simple repeating figures | Slightly off on purpose; pull MOTION down to steady it |
| **SPARK GAP** | A sync pluck that sparks on every note, with a ring two octaves up | C3–C6 | RHYTHM | Electro, industrial, synthwave | Fast arpeggios | Bright attack: pair with a darker pad |
| **DUSTED MALLET** | A soft mallet on a dusty record | C3–C6 | FOREGROUND | Lo-fi, trip-hop, film, ambient | Melodies and loops | The dust sits on its own layer, filtered with the note |
| **CUT WIRE** | A thin, rectified pluck with a buzzing octave edge | C3–C6 | RHYTHM | Industrial, post-punk, EBM | Riffs and arpeggios | High-passed at 350 Hz: it layers over anything |
| **SCAR PLUCK** | A sine pluck that flares into bell harmonics as you hit harder | C3–C6 | FOREGROUND | Industrial pop, film, electro | Melodic patterns with dynamics | Velocity is the timbre knob here |
| **ICICLE** | A high, brittle glass pluck with a faint shimmer | C5–C7 | TEXTURE | Film, ambient, winter-noir | Sparse high figures | Lives up high; it never gets in the way |
| **TWITCH** | A resonant pluck whose accents follow a syncopated pattern locked to the bar | C3–C6 | RHYTHM | Industrial techno, EBM, acid | Straight sixteenth notes; the accents make the groove | Pattern B is on the eighths; MOTION 0 plays every note the same |
| **PIANO WIRE** | A plucked piano wire: bright, ringing, a little crushed | C3–C6 | FOREGROUND | Gothic, film, industrial | Arpeggios and counterpoint | Rings for half a second; keep patterns open |

## ARP (16)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **PULSE WOUND** | A soft, tense sixteenth pulse with a ringing edge and a slightly broken sample rate | C3–C5 | RHYTHM | Film score, thriller, ambient, industrial ballads | Hold minor chords for a bar or two | Quiet tension under dialogue or a vocal; the filter opens over four bars |
| **MACHINE LOOM** | A saw sequence with a folded accent pattern of its own, locked to the bar | C3–C5 | RHYTHM | Industrial techno, EBM, darkwave | Hold chords; accents and arp interlock | Pattern B pushes harder for the drop; MOTION 0 plays every step alike |
| **NEEDLE RAIN** | Fast, random glass needles inside your chord, crushed at the edges | C3–C5 | TEXTURE | Glitch, IDM, film, ambient | Hold chords under something slower | Reads as texture, not melody; the notes only come from the chord you hold |
| **FEVER CLOCK** | A swung pulse arp in the order you play, ringing on the off-beats | C3–C5 | RHYTHM | Industrial, trip-hop, electro | Play chords note by note in the order you want | 30% swing: line your drums up with it |
| **RUST SPIRAL** | A rusty eighth-note spiral up and down three octaves, ringing as it goes | C3–C4 (it climbs) | FOREGROUND | Film, industrial, gothic | Hold two- or three-note chords low | Three octaves: keep the chord low or it climbs into the cymbals |
| **SIGNAL FLARE** | Crushed chord stabs stuttering in a gated pattern on the bar | C3–C5 | RHYTHM | Industrial, breakbeat, drum and bass, trailer | Hold chords; the gate is the rhythm | Pattern B builds; MOTION 0 plays every sixteenth |
| **COLD PULSE** | A plain sine pulse, gently shaped, with a shifted shadow drifting against it | C3–C5 | RHYTHM | Film score, thriller, minimal, ambient | Hold chords for long stretches | The shadow is where the unease lives; MOTION 0 makes it a clean pulse |
| **THROAT SEQUENCE** | A sequence that talks: the vowel glides through four shapes over two bars | C3–C5 | RHYTHM | Industrial, electro, darkwave | Hold chords for two bars | Vowels sit where a voice does; duck it under vocals |
| **GLASS TENSION** | Dotted-eighth glass rolling against the beat, edged with a rectified buzz | C3–C5 | RHYTHM | Film, post-rock, ambient | Hold chords for two bars; the 3-against-4 does the work | Pairs with a straight-sixteenth hat for the push and pull |
| **IRON STEPS** | Heavy eighth-note steps walking down two octaves, folded and crushed | C3–C5 | RHYTHM | Industrial rock, doom, trailer | Hold minor chords for a bar | Mid-heavy: carve 400 Hz from guitars under it |
| **DATA DROPLETS** | Random digital droplets from your chord, each one a different timbre | C3–C5 | TEXTURE | Glitch, IDM, sci-fi, industrial | Hold chords under a steady beat | Only chord notes play; the timbre changes every step in time |
| **HEARTBEAT MONITOR** | A slow, sparse pulse like a monitor in an empty room, with long echoes | C4–C6 | TEXTURE | Film score, thriller, ambient | Hold chords; one note per beat | Sparse on purpose; the echo fills the gaps |
| **SPARKING CHAIN** | A sparking sync arp with gaps knocked into its rhythm | C3–C5 | RHYTHM | Industrial, electro, EBM | Hold chords; the gaps line up with the bar | MOTION 0 fills the gaps in |
| **SUB MOTOR ARP** | A rolling bass arp with a clean sub under a folded top | C2–C4, sub an octave under | RHYTHM | Industrial techno, EBM, synthwave | Hold two- or three-note shapes low | Dry and mono in the lows; sidechain it to the kick |
| **ANXIETY** | A tight sixteenth pulse whose filter climbs for four bars and resets: a build that won't stop | C3–C5 | TRANSITION | Trailer, thriller, techno builds | Hold one chord through a four-bar build | The climb is on the song grid; start the chord on the bar |
| **LOST TRANSMISSION** | An arpeggio caught on a failing radio: band-passed, crushed, drifting off station | C3–C5 | TEXTURE | Trip-hop, film, industrial, hip-hop | Hold chords for two bars | Band-passed: it never touches the bass or the air |

## MOTION (18)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **IRON GATE** | Crushed supersaw chords chopped by a sixteenth gate; four patterns on the switch keys | C3–C5 | RHYTHM | Industrial, trance-noir, trailer, EBM | Hold chords; C1–D#1 switch patterns A–D | Start chords on the bar. MOTION 0 is the plain chord; halfway is a soft chop |
| **PISTON CHORDS** | Chords that duck and swell like a machine press, with accented filter hits | C3–C5 | RHYTHM | Industrial techno, EBM, big-room noir | Hold chords; the pump is on eighths | It pumps by itself; skip the sidechain or keep it light |
| **RATTLE CAGE** | Chords rattling inside a tuned cage: the comb steps between the note and its octaves | C3–C5 | RHYTHM | Industrial, sci-fi, IDM, film | Hold chords; switch keys change the rattle | Every step is an octave of the note, so it stays in key |
| **STUTTER HYMN** | A damaged organ hymn stuttering in three-against-four | C3–C5 | RHYTHM | Gothic, industrial, film | Hold chords; patterns B and C are the dotted feels | A hymn you can dance to: MOTION 0 for the plain organ in the bridge |
| **HEAVY BREATH** | A chord that breathes: in and out on the bar, through a throat-shaped filter | C3–C5 | TEXTURE | Horror, industrial, film, dark ambient | Hold chords for a bar or more | Pattern B breathes twice as fast: panic |
| **GRAIN CONVEYOR** | A chord carried along a belt of grain: the crush pulses in sixteenths | C3–C5 | RHYTHM | Industrial, glitch, minimal techno | Hold chords under drums | The crush is the groove; MOTION 0 leaves a lightly crushed chord |
| **VOWEL MACHINE** | A choir forced to speak a vowel sequence in eighths | C3–C5 | RHYTHM | Industrial, electro, film | Hold chords for two bars | Pattern B snaps between two vowels: a talk-box chug |
| **BROKEN METRONOME** | A chord with a metallic click on each beat, and a hiccup before the bar | C3–C5 | RHYTHM | Industrial, minimal, film | Hold chords | The ring clicks with the beat; pattern B is the dotted one |
| **DOPPLER BLADES** | Chords spinning past like blades: pan and filter swinging on the grid | C3–C5 | RHYTHM | Industrial, trailer, drum and bass | Hold chords | Wide in motion but centred on average; check mono, it holds up |
| **TREMOR** | A chord shaking with a fast tremolo whose speed and tone jump every eighth | C3–C5 | TEXTURE | Industrial, horror, noise | Hold chords under something steady | Nervous by design; MOTION scales the jumps |
| **OFFBEAT ENGINE** | Off-beat chord stabs, crushed, with four patterns on the switch keys | C3–C5 | RHYTHM | Industrial techno, EBM, dub-noir | Hold chords; stabs land between the kicks | The gaps leave the kick alone; no sidechain needed |
| **BITSTREAM** | A chord streamed through a failing data line: bit depth flickering in thirty-seconds | C3–C5 | TEXTURE | Glitch, IDM, industrial | Hold chords | Busy in the top end; a low-pass at 8 kHz on the bus keeps it off the hats |
| **SHIFT SWARM** | A chord with a shifted swarm sliding up and down around it in sixteenths | C3–C5 | TEXTURE | Sci-fi, industrial, experimental, horror | Hold chords | Inharmonic by nature; keep the chord simple and let the swarm do the rest |
| **BLOOD PUMP** | A chord that beats like a heart: lub-dub once a bar (twice on pattern B) | C3–C5 | RHYTHM | Horror, thriller, film, dark ambient | Hold chords; set the tempo to the heart rate you want | At 60–80 BPM it is a resting heart; push the tempo for panic |
| **CHAIN GANG** | Chords struck like chains: feedback and a comb flaring on a work-song rhythm | C3–C5 | RHYTHM | Industrial, blues-noir, film | Hold chords under a slow beat | The flares are loud for a moment; a slow compressor keeps them even |
| **DEAD AIR MORSE** | A chord keyed like morse code over a dead radio channel, then silence | C3–C5 | TEXTURE | Film, sci-fi, thriller, ambient | Hold chords; half of every bar is empty | The empty half is for something else to answer it |
| **TIDAL MACHINE** | A slow two-bar tide under a fast sixteenth pulse: two performers against each other | C3–C5 | RHYTHM | Progressive, industrial, trailer | Hold chords for two bars | Performer 1 is the tide, 2 the pulse; MOTION scales both |
| **CONVULSION** | Chords in spasm: a broken gate and a crush sequence fighting each other; four patterns | C3–C5 | RHYTHM | Industrial, breakcore, glitch, trailer | Hold chords; switch patterns with the keys for fills | The most violent motion preset. MOTION halfway is still usable under a vocal |

## DRONE (18)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **DREAD ENGINE** | A low saw engine whose filter slowly opens and feeds back on itself | D1–D3 | SUPPORT | Film score, trailer, industrial, dark ambient | Hold a root and fifth for bars | Mono below 150 Hz; sits under anything. MOTION 0 is a steady hum |
| **FERROUS HUM** | An electrical hum through iron: buzzing pulse, ringing octaves, broken sample rate | D1–D3 | TEXTURE | Industrial, horror, sci-fi, noise | Hold one note; the machine does the rest | Buzzy in the mids: a band cut at 1–2 kHz pushes it into the background |
| **CATHEDRAL ROT** | A choir rotting in a stone room: vowels drift, a comb rings, a filter loop hums under it | D2–D4 | TEXTURE | Film score, doom, gothic, horror | Long held notes and fifths | Long release: end it early before a cut |
| **BLACK TIDE** | A low swell that rolls in and out over four bars, with a dark surf of noise | D1–D3 | SUPPORT | Trailer, dark ambient, doom, film | Hold a low note through a whole section | The swell follows the bar; start it on a downbeat |
| **BOWED GIRDER** | A steel girder bowed until it sings: metal noise ringing a comb tuned to the note | D2–D4 | TEXTURE | Horror, film score, industrial, experimental | Long notes; the swell takes three seconds | Band-passed: it sits in the middle and never muddies the lows |
| **NERVE HUM** | A sine hum rectified into a buzz, beating slowly against a shifted copy | D2–D4 | TEXTURE | Film score, thriller, minimal, horror | Hold single notes | The beating is slow: tension without melody |
| **TAPE GRAVE** | An organ chord buried on an old tape: wow, dust and a broken sample rate | D2–D4 | TEXTURE | Film score, lo-fi, horror, ambient | Hold chords or fifths | The wow is up to 7 cents; MOTION 0 steadies it against tuned parts |
| **SULFUR** | A dark detuned drone with a tritone ring breathing in and out | D1–D3 | TEXTURE | Horror, doom, industrial | Hold single notes | Dissonant by design; MOTION 0 keeps the ring faint |
| **PRESSURE CHAMBER** | Pressure building for four bars as the filter loop begins to howl, then release | D1–D3 | TRANSITION | Trailer, thriller, industrial builds | Hold a note through four-bar builds | The build follows the song grid; MOTION sets how hard it howls |
| **RADIATION** | A Geiger-counter drone: digital noise crackling over a crushed tone | D2–D4 | TEXTURE | Sci-fi, horror, noise, industrial | Hold a note under a scene | The crackle jumps in eighths on MOTION; band-passed, so it stays out of the lows |
| **DEEP STRUCTURE** | A low FM drone whose metal grows and fades over four bars | D1–D3 | SUPPORT | Film score, sci-fi, ambient | Hold single low notes | The FM ratio is a twelfth, so the partials stay harmonic |
| **HOLLOW SIGNAL** | A hollow voice drone speaking four slow vowels over four bars | D2–D4 | TEXTURE | Horror, dark ambient, film | Hold one note through a scene | Vowels follow the bar; MOTION 0 holds one |
| **RUST FIELD** | A combed, folded drone sweeping slowly through rust-coloured harmonics | D1–D3 | TEXTURE | Industrial, doom, film | Hold notes for bars | Four-bar sweep: pair it with section changes |
| **WAR ROOM** | A low drone that throbs on every beat, like a war-room hum under a briefing | D1–D3 | SUPPORT | Thriller, trailer, film score | Hold a low note under a scene | The throb is on the beat; it keeps tension without drums |
| **SINGING WIRE** | A resonant filter loop tuned to the note until it sings like feedback from an amp | D2–D4 | TEXTURE | Noise rock, film, industrial, ambient | Hold single notes | It rises and falls in volume on its own over four bars |
| **GLASS STORM** | A high cloud of glass, shifted and crushed, blown around slowly | D3–D5 | TEXTURE | Film score, ambient, sci-fi | Hold notes high above everything | High-passed at 200 Hz: pure atmosphere, no weight |
| **SUBTERRANEAN** | The low, hollow resonance of something enormous underground | D1–D3 | SUPPORT | Trailer, doom, horror, dark ambient | Hold one low note | Mono and dark; ride TONE up for the reveal |
| **ASH RAIN** | A soft chord under falling ash: crackle, crush and a slow sweep | D2–D4 | TEXTURE | Film score, post-apocalyptic, ambient | Hold chords or fifths | Gentle enough to sit under dialogue |

## PERC (12)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **PISTON KICK** | A folded, clipped kick for machine rhythms | Tune around C1–G1 | RHYTHM | Industrial, EBM, industrial techno, hip-hop | One note per hit; the note sets the tuning | MOTION is the pitch-drop punch; hard hits fold more. Keep the bass off 50–70 Hz |
| **BLOWN KICK** | A kick through a blown speaker: long, saturated, the tail growling | Tune around C1–G1 | RHYTHM | Industrial rock, trap, noise, trailer | Sparse hits with room to ring | It is kick and sub at once; drop the bass under it or sidechain hard |
| **ANVIL SNARE** | A snare with an anvil in it: noise, a short body and a metal ring | Around D2 | RHYTHM | Industrial rock, EBM, trailer | Backbeats; the ring changes hit to hit on MOTION | The ring is at 1–3 kHz; it cuts through guitars without extra level |
| **CRUSHED SNARE** | A snare ground down to bits and aliasing | Around D2 | RHYTHM | Industrial, glitch, hip-hop, breakbeat | Backbeats and ghost notes | Each hit crushes differently on MOTION; hard velocity adds noise |
| **SHEET METAL** | A sheet of metal struck and ringing, inharmonic and different every hit | Any; C3–C5 reads as a clang | RHYTHM | Industrial, film, horror, percussion ensembles | Accents and fills; play different notes for different sheets | Rings for half a second: sparse accents, not every beat |
| **HAMMER TOM** | A tuned tom struck with a hammer: pitch-dropping thud with a wrinkled tone | C1–C3; play fills across notes | RHYTHM | Industrial, tribal-noir, trailer | Tom fills and tribal patterns across several notes | MOTION sets the pitch drop; velocity the wrinkle |
| **STATIC HAT** | A digital hi-hat: static and aliasing, each hit a little different | Any | RHYTHM | Industrial, glitch, techno, hip-hop | Eighths and sixteenths | Very bright: it sits above everything at a low level |
| **CHAIN SHAKE** | Chains shaken in rhythm: metal jangle that changes every step | Any | RHYTHM | Industrial, work-song, film, trip-hop | Shaker patterns in eighths or sixteenths | Use it instead of a shaker for grime |
| **GLASS BREAK** | A pane of glass breaking: a burst and inharmonic shards | Any; higher notes are smaller panes | TRANSITION | Film, horror, industrial, sound design | Accents and impacts | Place it on a cut or a downbeat; it layers well over a snare |
| **RIVET CLICK** | A rivet gun click: tiny, tuned, a little crushed | C4–C7 sets the pitch of the click | RHYTHM | Industrial, IDM, minimal, glitch | Fast patterns; use as a hat or a tick | Tiny: it adds articulation to a beat, not weight |
| **BODY BLOW** | A dull, heavy thump like a fist on a body: impact without a clear pitch | Around E1–E2 | RHYTHM | Film, fight scenes, industrial, trailer | Impacts and heavy off-beats | Layer under a snare for weight, or use alone for impacts |
| **IRON CLAP** | A clap with a metal ring and a broken sample rate; the flams are built in | Any | RHYTHM | Industrial, EBM, hip-hop, techno | Backbeats | Layer with a snare for the classic industrial backbeat |

## FX (16)

| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |
|---|---|---|---|---|---|---|
| **TENSION RISER** | A two-bar riser: filter, shift and feedback all climbing from the key press | C3–C5 | TRANSITION | Trailer, EDM-noir, industrial, film | Hold a note two bars before the drop | Starts when you press the key, so place it two bars early; MOTION sets how far it climbs |
| **DOWNFALL** | A fall: pitch dives an octave while the sample rate crumbles | C3–C5 | TRANSITION | Trailer, industrial, film, bass music | Hit it on the last beat before a break | The dive takes about two seconds regardless of tempo |
| **RADIO GHOSTS** | Tuning through a dead band: voices, whistles and static drifting past | C3–C5 | TEXTURE | Film, horror, sci-fi, trip-hop | Hold under a scene or an intro | Band-passed, so it sits anywhere; automate TONE to tune it |
| **HYDRAULIC** | Hydraulic pistons venting air in rhythm | Any | TEXTURE | Industrial, sci-fi, film, techno | Hold for a mechanical texture; pattern B chops it | Place it in the gaps between drums |
| **IMPACT BLOOM** | A hit that blooms into a long, crushed tail in a big room | C1–C3 for weight | TRANSITION | Trailer, film, industrial | One hit on a downbeat or a cut | The tail runs two seconds; leave space after it |
| **ALARM DECAY** | A siren wailing and fading into a big space | C3–C5 | TRANSITION | Film, industrial, trailer, horror | Hold for an alarm; release to let it fade | The wail is on MOTION; 0 is a steady tone |
| **SWARM** | An insect swarm of ring-modulated, crushed buzzing | C3–C6 | TEXTURE | Horror, sci-fi, industrial, noise | Hold under a scene; bend for panic | Band-passed and busy; keep it low in the mix |
| **TAPE STOP** | A chord that grinds to a halt like a stopped tape, crumbling as it slows | C3–C5 | TRANSITION | Industrial, hip-hop, trailer, electronic breaks | Hit a chord on the last beat before a gap | The stop takes about a second; release the keys when you want silence |
| **VACUUM** | A reverse-style swell sucked in over two seconds and cut dead | C3–C5 | TRANSITION | Trailer, EDM-noir, film, industrial | Press two seconds before the downbeat, release on it | The cut is the release: let go exactly on the beat |
| **STATIC STORM** | A storm of digital static bursting in thirty-seconds | Any | TEXTURE | Glitch, industrial, sci-fi, horror | Hold for bursts of interference | Very bright; keep it short or low |
| **SUB DROP** | A sine sub dropping an octave into the floor, with a wrinkled edge | C1–C3 | TRANSITION | Trailer, trap, bass music, film | One hit on a downbeat after a build | Huge in the lows: nothing else should play 30–80 Hz under it |
| **SIGNAL LOSS** | A clean tone that crumbles and drops out over two bars, like a signal dying | C3–C5 | TRANSITION | Film, sci-fi, thriller, industrial outros | Hold a note or chord for two bars | Starts on the key: press it two bars before the cut |
| **METAL FATIGUE** | The groan of a steel structure under load | C1–C3 | TEXTURE | Horror, film, submarine, industrial | Hold low notes for creaks and groans | Low and moving; sits under a scene without melody |
| **GLITCH SPRAY** | A spray of glitches: pitch jumping by octaves in thirty-seconds, gated and crushed | C3–C5 | TRANSITION | Glitch, IDM, industrial, fills | Short hits as fills; hold longer for chaos | The pitch jumps are octaves of the note, so it still fits the key |
| **HOLLOW WIND** | Wind moaning through a hollow structure, gusting on its own | Any | TEXTURE | Film, horror, ambient, western-noir | Hold under a scene | No pitch, so it sits under any key |
| **PRESSURE RELEASE** | A burst of air as a seal gives, the hiss falling away over a second | Any | TRANSITION | Industrial, sci-fi, film, transitions | One hit on a transition | Bright at the start: great on a cut, too much on every bar |
