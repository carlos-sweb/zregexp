# Análisis Comparativo de Motores Regex
## Solución al Bug de Infinite Loop en SPLIT

**Fecha**: 2025-12-01
**Autor**: Análisis técnico de implementaciones
**Propósito**: Determinar la mejor solución para el bug de SPLIT en zregexp

---

## 1. Resumen Ejecutivo

Este documento analiza tres enfoques diferentes para implementar motores de expresiones regulares, con el objetivo de resolver el bug de infinite loop que ocurre en instrucciones SPLIT (cuantificadores `*`, `+`, `?` y alternación `|`).

### Tres Enfoques Analizados:

1. **zregexp (actual)**: Pike VM con colas de threads paralelos
2. **QuickJS libregexp**: Backtracking con stack explícito
3. **mvzr**: Matching recursivo con backtracking

### Recomendación Final:

**Adoptar el enfoque de mvzr (recursive matching)** por las siguientes razones:
- ✅ Compatible con Zig 0.15 (probado)
- ✅ Código más simple y mantenible
- ✅ No requiere visited set ni gestión compleja de threads
- ✅ Backtracking natural mediante recursión
- ✅ Menor uso de memoria que stack explícito

---

## 2. Análisis Detallado de Cada Enfoque

### 2.1 zregexp (Pike VM) - ENFOQUE ACTUAL ❌

#### Arquitectura:
```
Pike VM = Simulación de NFA con threads paralelos
- current_queue: threads activos en posición actual
- next_queue: threads para siguiente posición
- visited: HashMap para evitar loops infinitos
```

#### Implementación SPLIT (vm.zig:218-234):
```zig
.SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY => {
    const offset1 = @as(i32, @bitCast(inst.operands[0]));
    const offset2 = @as(i32, @bitCast(inst.operands[1]));

    const pc1: usize = @intCast(@as(i32, @intCast(current.pc)) + offset1);
    const pc2: usize = @intCast(@as(i32, @intCast(current.pc)) + offset2);

    // Crear segundo thread
    var thread2 = current.clone();
    thread2.pc = pc2;
    try self.current_queue.add(thread2);

    // Continuar con primer thread
    current.pc = pc1;
},
```

#### Problema Fundamental:

El Pike VM maneja transiciones epsilon (instrucciones que no consumen caracteres) explorando todos los caminos en paralelo. Para cuantificadores como `a*`:

```
Bytecode para "a*":
  0: SPLIT offset1=+2, offset2=+5
  2: CHAR 'a'
  3: GOTO -3  ← Vuelve a pc=0
  5: MATCH

Ejecución con input "aaa":
  sp=0, pc=0: SPLIT → Thread1(pc=2), Thread2(pc=5)
  sp=0, pc=2: Thread1 consume 'a' → (pc=3, sp=1)
  sp=1, pc=3: GOTO -3 → (pc=0, sp=1)  ← PROBLEMA
  sp=1, pc=0: SPLIT otra vez...

Loop infinito: (pc=0, sp=0) → (pc=0, sp=1) → (pc=0, sp=2) → ...
```

#### Solución Intentada: Visited Set

```zig
visited: HashMap(ThreadState, void)

// En GOTO:
const state = ThreadState{ .pc = new_pc, .sp = current.sp };
if (self.visited.contains(state)) {
    return ExecResult{ .matched = false };  // Bloquear loop
}
try self.visited.put(state, {});
```

**Problema**: El visited set es demasiado agresivo:
- Bloquea `(pc=0, sp=1)` porque ya visitó `(pc=0, sp=0)`
- Pero `(pc=0, sp=1)` es un estado VÁLIDO (consumió un 'a')
- Resultado: `"a*"` no puede consumir `"aaa"` greedily

#### Pros:
- ✅ Teóricamente elegante (basado en teoría de autómatas)
- ✅ Permite paralelización futura
- ✅ Soporta lookahead/lookbehind sin modificaciones

#### Contras:
- ❌ Complejidad en epsilon-closure
- ❌ Visited set difícil de implementar correctamente
- ❌ Greedy vs lazy requiere lógica adicional
- ❌ Mayor uso de memoria (dos colas, visited set)
- ❌ **Bug actual no resuelto después de 6 intentos**

---

### 2.2 QuickJS libregexp (Stack-based Backtracking) ✅

#### Arquitectura:
```
Backtracking Engine = Stack explícito de estados alternativos
- Stack: Array de estados (pc, string_pos, captures)
- Ejecución lineal con push/pop en bifurcaciones
```

#### Implementación SPLIT (libregexp.c:2828-2848):
```c
case REOP_split_next_first:
case REOP_split_goto_first:
    {
        // Guardar estado alternativo en stack
        sp[0].ptr = (uint8_t *)pc1;      // PC alternativo
        sp[1].ptr = (uint8_t *)cptr;     // String pos alternativo
        sp[2].val = (uintptr_t)re_save; // Captures alternativas
        sp[2].bp.type = RE_EXEC_STATE_SPLIT;
        sp += 3;  // Push 3 elementos

        // Continuar con primer camino
        pc = pc;  // (o pc = pc1 según tipo)
        break;
    }

// En caso de fallo (línea 2729):
no_match:
    // Pop del stack
    if (sp == stack_buf) {
        ret = 0;  // No más alternativas, fallo total
        goto fail;
    }

    // Restaurar estado alternativo
    sp -= 3;
    pc = sp[0].ptr;
    cptr = sp[1].ptr;
    re_save = (uint8_t *)sp[2].val;

    // Continuar desde estado guardado
    goto restart;
```

#### Cómo Maneja `"a*"` con `"aaa"`:

```
Pattern: a*
Bytecode:
  0: REOP_split_next_first offset_greedy, offset_skip
  2: REOP_char 'a'
  3: REOP_goto -3
  5: REOP_match

Ejecución:
  1. pc=0, pos=0: SPLIT
     - Push stack: (pc=5, pos=0)  ← Alternativa: skip star
     - Continue: pc=2

  2. pc=2, pos=0: char 'a' ✓
     - pos=1, pc=3

  3. pc=3, pos=1: GOTO -3
     - pc=0, pos=1

  4. pc=0, pos=1: SPLIT
     - Push stack: (pc=5, pos=1)  ← Alternativa: stop here
     - Continue: pc=2

  5. pc=2, pos=1: char 'a' ✓
     - pos=2, pc=3

  6. pc=3, pos=2: GOTO -3
     - pc=0, pos=2

  7. pc=0, pos=2: SPLIT
     - Push stack: (pc=5, pos=2)
     - Continue: pc=2

  8. pc=2, pos=2: char 'a' ✓
     - pos=3, pc=3

  9. pc=3, pos=3: GOTO -3
     - pc=0, pos=3

  10. pc=0, pos=3: SPLIT
      - Push stack: (pc=5, pos=3)
      - Continue: pc=2

  11. pc=2, pos=3: char 'a' ✗ (fin de string)
      - Goto no_match

  12. no_match:
      - Pop stack: (pc=5, pos=3)
      - pc=5: MATCH ✓

Resultado: Match en pos=3 (consumió "aaa" completo)
```

**Clave**: El stack naturalmente previene loops infinitos porque:
- Cada SPLIT agrega UN estado alternativo
- El stack tiene profundidad máxima = longitud del input
- Backtracking consume stack (pop)

#### Pros:
- ✅ Probado en producción (QuickJS usado en millones de proyectos)
- ✅ No requiere visited set
- ✅ Backtracking natural y eficiente
- ✅ Greedy/lazy fácil de implementar (orden de push)

#### Contras:
- ❌ Requiere portar lógica de C a Zig
- ❌ Stack explícito más complejo que recursión
- ❌ Peor caso: O(2^n) tiempo con patterns patológicos

---

### 2.3 mvzr (Recursive Matching) ✅✅

#### Arquitectura:
```
Recursive Matcher = Funciones recursivas con backtracking
- matchPattern(): Dispatcher principal
- matchStar(), matchPlus(), matchQuestion(): Handlers de cuantificadores
- Recursión natural del lenguaje
```

#### Implementación STAR (mvzr.zig:452-500):
```zig
fn matchStar(
    patt: []const RegOp,
    sets: []const CharSet,
    haystack: []const u8,
    i_in: usize
) OpMatch {
    var i = i_in;
    const this_patt = thisPattern(patt);
    const next_patt = nextPattern(patt);

    // FASE 1: Consumo greedy (máximo posible)
    while (matchPattern(this_patt, sets, haystack, i)) |m| {
        i = m.i;
        if (i == haystack.len or i == i_in) break;
    }

    // FASE 2: Intentar match del siguiente pattern
    const maybe_next = matchPattern(next_patt, sets, haystack, i);
    if (maybe_next) |m2| {
        return m2;  // Éxito total
    }

    // FASE 3: Backtracking (retroceder hasta encontrar match)
    i = if (i == i_in) i_in else (i - 1);

    while (true) {
        // Intentar siguiente pattern desde posición anterior
        const try_next = matchPattern(next_patt, sets, haystack, i);
        if (try_next) |m2| {
            // Verificar que this_patt aún matchea
            if (matchPattern(this_patt, sets, haystack, i)) |_| {
                return m2;  // Encontrado punto de split correcto
            }
        }

        // Retroceder más
        if (i == i_in) break;  // No más backtracking posible
        i -= 1;
    }

    // Fallo: retornar posición inicial
    return OpMatch{ .i = i_in, .j = next_patt };
}
```

#### Cómo Maneja `"a*"` con `"aaa"`:

```
Pattern: a*
Input: "aaa"

1. matchStar(patt=["a*", ...], haystack="aaa", i=0)

   FASE 1 - Consumo greedy:
   - matchPattern("a", "aaa", 0) → i=1 ✓
   - matchPattern("a", "aaa", 1) → i=2 ✓
   - matchPattern("a", "aaa", 2) → i=3 ✓
   - matchPattern("a", "aaa", 3) → fail (fin)
   - Consumido: i=3 (toda la string)

   FASE 2 - Intentar siguiente pattern:
   - next_patt = <end-of-pattern>
   - matchPattern(<end>, "aaa", 3)
   - ¿i==haystack.len? → 3==3 ✓
   - Return OpMatch{ .i = 3 } ← ÉXITO

Resultado: Match completo en posición 3
```

#### Ejemplo con Backtracking `"a*b"` con `"aaab"`:

```
Pattern: a*b
Input: "aaab"

1. matchStar(patt=["a*", "b"], haystack="aaab", i=0)

   FASE 1:
   - Consume "aaa" → i=3

   FASE 2:
   - matchPattern("b", "aaab", 3)
   - haystack[3] = 'b' ✓
   - Return OpMatch{ .i = 4 } ← ÉXITO sin backtracking
```

#### Ejemplo con Backtracking `"a*a"` con `"aaa"`:

```
Pattern: a*a
Input: "aaa"

1. matchStar(patt=["a*", "a"], haystack="aaa", i=0)

   FASE 1:
   - Consume "aaa" → i=3

   FASE 2:
   - matchPattern("a", "aaa", 3) → fail (no hay más chars)

   FASE 3 - Backtracking:
   - i = 2 (retroceder)
   - matchPattern("a", "aaa", 2)
   - haystack[2] = 'a' ✓
   - Return OpMatch{ .i = 3 } ← ÉXITO después de backtrack
```

**Clave**: No hay infinite loop porque:
- `while (true)` tiene condición de salida: `if (i == i_in) break`
- `i` siempre decrementa: `i -= 1`
- Máximo de iteraciones = longitud consumida en FASE 1

#### Pros:
- ✅✅ **Código más simple y legible**
- ✅ Compatible con Zig 0.15 (ya probado en mvzr)
- ✅ No requiere visited set
- ✅ No requiere stack explícito
- ✅ Backtracking natural del lenguaje
- ✅ Fácil de debuggear (stack trace del lenguaje)
- ✅ Menor uso de memoria que stack explícito

#### Contras:
- ❌ Peor caso: O(2^n) con patterns patológicos
- ❌ Profundidad de recursión limitada por stack del sistema
- ❌ No paralelizable (ejecución secuencial)

---

## 3. Comparación Side-by-Side

| Característica | Pike VM (zregexp) | QuickJS Stack | mvzr Recursive |
|----------------|-------------------|---------------|----------------|
| **Complejidad** | ⚠️ Alta | ⚠️ Media | ✅ Baja |
| **Líneas de código** | ~300 | ~400 | ~150 |
| **Infinite loop** | ❌ Bug actual | ✅ Resuelto | ✅ Resuelto |
| **Memoria** | Alta (2 queues + visited) | Media (stack) | Baja (recursión) |
| **Debuggeable** | ❌ Difícil | ⚠️ Medio | ✅ Fácil |
| **Compatible Zig 0.15** | ✅ Sí | ❓ Requiere porting | ✅ Probado |
| **Greedy/Lazy** | ❌ No implementado | ✅ Nativo | ✅ Nativo |
| **Backtracking** | ❌ Problemático | ✅ Stack | ✅ Recursión |
| **Paralelizable** | ✅ Posible | ❌ No | ❌ No |
| **Peor caso** | O(n*m) | O(2^n) | O(2^n) |
| **Caso promedio** | O(n*m) | O(n) | O(n) |

**Leyenda**: n = longitud input, m = complejidad del pattern

---

## 4. Recomendación Final

### **Adoptar enfoque de mvzr (Recursive Matching)**

#### Razones Técnicas:

1. **Simplicidad**: 50% menos código que Pike VM
2. **Probado**: mvzr ya funciona con Zig 0.15
3. **Mantenibilidad**: Lógica clara y fácil de seguir
4. **No requiere visited set**: El backtracking es bounded naturalmente
5. **Debuggeable**: Stack traces del lenguaje muestran exactamente qué pattern está fallando

#### Plan de Implementación (3-4 horas):

```
Fase 1: Crear matcher.zig recursivo (1.5h)
├── matchPattern() - dispatcher principal
├── matchLiteral() - caracteres literales
├── matchDot() - punto (.)
├── matchStar() - cuantificador *
├── matchPlus() - cuantificador +
├── matchQuestion() - cuantificador ?
└── matchAlternation() - alternación |

Fase 2: Integrar con API existente (1h)
├── Mantener Regex.compile() (API pública)
├── Reemplazar VM.execute() con matchPattern()
└── Adaptar ExecResult para recursion

Fase 3: Tests (0.5h)
├── Re-habilitar los 33 tests deshabilitados
├── Verificar que todos pasen
└── Benchmark vs versión anterior

Fase 4: Documentación (1h)
├── Actualizar ARCHITECTURE.md
├── Comentar código nuevo
└── Actualizar PROGRESS_PHASE3.md
```

#### Código Base a Portar de mvzr:

```zig
// mvzr.zig:452-500 - matchStar()
// mvzr.zig:502-531 - matchPlus()
// mvzr.zig:389-450 - matchPattern() dispatcher
```

#### Ventajas vs QuickJS:

- ✅ Menos líneas de código (150 vs 400)
- ✅ No requiere gestión manual de stack
- ✅ Ya en Zig (no porting de C)
- ✅ Más idiomático para Zig

---

## 5. Plan de Acción Detallado

### Paso 1: Crear estructura base (30 min)

**Archivo**: `/root/libzregxp/zregexp/src/executor/recursive_matcher.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const opcodes = @import("../bytecode/opcodes.zig");
const format = @import("../bytecode/format.zig");

/// Resultado de matching
pub const MatchResult = struct {
    matched: bool,
    end_pos: usize,
    captures: ?[]CaptureGroup = null,
};

/// Capture group
pub const CaptureGroup = struct {
    start: ?usize = null,
    end: ?usize = null,

    pub fn isValid(self: CaptureGroup) bool {
        return self.start != null and self.end != null;
    }
};

/// Recursive matcher
pub const RecursiveMatcher = struct {
    allocator: Allocator,
    bytecode: []const u8,
    input: []const u8,
    captures: [16]CaptureGroup,  // Máximo 16 grupos

    const Self = @This();

    pub fn init(allocator: Allocator, bytecode: []const u8, input: []const u8) Self {
        return .{
            .allocator = allocator,
            .bytecode = bytecode,
            .input = input,
            .captures = [_]CaptureGroup{.{}} ** 16,
        };
    }

    /// Match desde posición específica
    pub fn matchFrom(self: *Self, pc: usize, pos: usize) !MatchResult {
        // TODO: Implementar lógica recursiva
    }

    /// Helper: match literal character
    fn matchChar(self: *Self, pc: usize, pos: usize, expected: u8) !MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        if (self.input[pos] != expected) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        // Continue with next instruction
        const inst = try format.decodeInstruction(self.bytecode, pc);
        return self.matchFrom(pc + inst.size, pos + 1);
    }

    /// Helper: match star quantifier (greedy)
    fn matchStar(self: *Self, pc: usize, pos: usize, char_pc: usize) !MatchResult {
        var current_pos = pos;

        // PHASE 1: Greedy consumption
        while (current_pos < self.input.len) {
            const before_match = try self.matchFrom(char_pc, current_pos);
            if (!before_match.matched) break;
            current_pos = before_match.end_pos;
        }

        // PHASE 2: Try to match rest of pattern
        const rest_result = try self.matchFrom(pc, current_pos);
        if (rest_result.matched) {
            return rest_result;
        }

        // PHASE 3: Backtrack
        while (current_pos > pos) {
            current_pos -= 1;
            const rest_result2 = try self.matchFrom(pc, current_pos);
            if (rest_result2.matched) {
                return rest_result2;
            }
        }

        // Failed
        return MatchResult{ .matched = false, .end_pos = pos };
    }
};
```

### Paso 2: Implementar dispatcher principal (30 min)

```zig
pub fn matchFrom(self: *Self, pc: usize, pos: usize) !MatchResult {
    if (pc >= self.bytecode.len) {
        return MatchResult{ .matched = false, .end_pos = pos };
    }

    const inst = try format.decodeInstruction(self.bytecode, pc);

    switch (inst.opcode) {
        .MATCH => {
            return MatchResult{ .matched = true, .end_pos = pos };
        },

        .CHAR32 => {
            const expected = @as(u8, @intCast(inst.operands[0]));
            return self.matchChar(pc, pos, expected);
        },

        .CHAR => {
            // Match any char (dot)
            if (pos >= self.input.len) {
                return MatchResult{ .matched = false, .end_pos = pos };
            }
            return self.matchFrom(pc + inst.size, pos + 1);
        },

        .SPLIT => {
            // For star quantifier: offset1 → char, offset2 → skip
            const offset1 = @as(i32, @bitCast(inst.operands[0]));
            const offset2 = @as(i32, @bitCast(inst.operands[1]));

            const pc1: usize = @intCast(@as(i32, @intCast(pc)) + offset1);
            const pc2: usize = @intCast(@as(i32, @intCast(pc)) + offset2);

            // Detect if this is a star loop
            // (check if offset1 points to CHAR followed by GOTO back)
            return self.matchStar(pc2, pos, pc1);
        },

        // ... otros opcodes

        else => {
            return MatchResult{ .matched = false, .end_pos = pos };
        },
    }
}
```

### Paso 3: Integrar con API existente (30 min)

**Modificar**: `/root/libzregxp/zregexp/src/executor/matcher.zig`

```zig
const RecursiveMatcher = @import("recursive_matcher.zig").RecursiveMatcher;

pub fn matchFull(self: Self, input: []const u8) !bool {
    // Usar RecursiveMatcher en vez de VM
    var matcher = RecursiveMatcher.init(self.allocator, self.bytecode, input);
    const result = try matcher.matchFrom(0, 0);

    // Verificar que consumió todo el input
    return result.matched and result.end_pos == input.len;
}
```

### Paso 4: Re-habilitar tests (15 min)

**Modificar**: `/root/libzregxp/zregexp/tests/integration_tests.zig`

Descomentar los 33 tests:

```zig
test "Integration: star quantifier" {
    var re = try Regex.compile(std.testing.allocator, "ab*c");
    defer re.deinit();
    try std.testing.expect(try re.test_("ac"));
    try std.testing.expect(try re.test_("abc"));
    try std.testing.expect(try re.test_("abbc"));
}

test "Integration: alternation" {
    var re = try Regex.compile(std.testing.allocator, "cat|dog|bird");
    defer re.deinit();
    try std.testing.expect(try re.test_("cat"));
    try std.testing.expect(try re.test_("dog"));
    try std.testing.expect(try re.test_("bird"));
}

// ... resto de tests comentados
```

### Paso 5: Ejecutar tests (5 min)

```bash
zig build test
```

**Resultado esperado**: 277/277 tests passing ✅

---

## 6. Métricas de Éxito

| Métrica | Antes (Pike VM) | Después (Recursive) |
|---------|-----------------|---------------------|
| Tests passing | 244/277 (88%) | 277/277 (100%) |
| Líneas en vm.zig | 310 | ~200 |
| Complejidad ciclomática | 18 | ~10 |
| Infinite loops | ❌ Sí | ✅ No |
| Greedy quantifiers | ❌ No | ✅ Sí |
| Tiempo de implementación | ~8 horas | ~4 horas |

---

## 7. Riesgos y Mitigaciones

### Riesgo 1: Stack overflow con patterns complejos
**Probabilidad**: Baja
**Impacto**: Alto
**Mitigación**:
- Agregar límite de profundidad recursiva (ej: 1000 niveles)
- Documentar limitaciones en README

### Riesgo 2: Performance peor que Pike VM
**Probabilidad**: Baja
**Impacto**: Medio
**Mitigación**:
- Benchmark antes y después
- Optimizar hot paths con inline
- Para casos extremos, mantener VM como fallback

### Riesgo 3: Incompatibilidad con bytecode existente
**Probabilidad**: Muy baja
**Impacto**: Alto
**Mitigación**:
- Reutilizar mismo bytecode format
- Tests garantizan compatibilidad

---

## 8. Conclusión

El enfoque de **recursive matching (mvzr)** es la solución óptima para resolver el bug de SPLIT infinite loop en zregexp porque:

1. **Probado**: Ya funciona en mvzr con Zig 0.15
2. **Simple**: 50% menos código que Pike VM
3. **Mantenible**: Lógica clara y debuggeable
4. **Completo**: Resuelve greedy/lazy/backtracking naturalmente
5. **Rápido de implementar**: 3-4 horas vs semanas depurando Pike VM

La implementación puede comenzar inmediatamente siguiendo el plan de 4 pasos detallado en la sección 5.

---

**Referencias**:
- QuickJS libregexp: `/root/libzregxp/quickjs/libregexp.c`
- mvzr: `/root/libzregxp/mvzr/src/mvzr.zig`
- zregexp VM actual: `/root/libzregxp/zregexp/src/executor/vm.zig`
