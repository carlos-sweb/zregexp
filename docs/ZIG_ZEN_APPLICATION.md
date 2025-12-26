# Aplicación del Zig Zen en zregexp

Este documento explica cómo aplicamos los principios del **Zig Zen** en el proyecto zregexp.

---

## Los 13 Principios del Zig Zen

```
 * Communicate intent precisely.
 * Edge cases matter.
 * Favor reading code over writing code.
 * Only one obvious way to do things.
 * Runtime crashes are better than bugs.
 * Compile errors are better than runtime crashes.
 * Incremental improvements.
 * Avoid local maximums.
 * Reduce the amount one must remember.
 * Focus on code rather than style.
 * Resource allocation may fail; resource deallocation must succeed.
 * Memory is a resource.
 * Together we serve the users.
```

---

## Aplicación en zregexp

### 1. **Communicate intent precisely**
✅ **Aplicado**:
- Nombres claros y descriptivos: `matchStarGreedy()`, `matchStarLazy()`, `matchStarPossessive()`
- Funciones con un solo propósito claro
- Comentarios que explican el "por qué", no el "qué"

🔄 **Mejoras a aplicar**:
- Renombrar funciones ambiguas
- Agregar documentación de intención en funciones complejas
- Usar tipos más expresivos donde sea posible

**Ejemplo**:
```zig
// ❌ ANTES: Intent no claro
fn process(self: *Self, data: []const u8) !void

// ✅ DESPUÉS: Intent preciso
fn matchPatternAgainstInput(self: *Self, input: []const u8) !MatchResult
```

---

### 2. **Edge cases matter**
✅ **Aplicado**:
- Manejo de input vacío: `if (pos >= self.input.len)`
- Manejo de bytecode vacío: `if (pc >= self.bytecode.len)`
- Verificación de límites en todas las operaciones

⚠️ **Pendiente**:
- Mejorar manejo de UTF-8 multi-byte
- Casos edge en alternation (actualmente bug)
- Patrones vacíos: `""`

**Ejemplo actual**:
```zig
// ✅ Verificamos edge cases
if (pos >= self.input.len) {
    return MatchResult{ .matched = false, .end_pos = pos };
}
```

---

### 3. **Favor reading code over writing code**
✅ **Aplicado**:
- Código explícito sin macros
- No hay control flow oculto
- Estructura clara y predecible

🔄 **Mejoras**:
- Preferir `for` sobre `while` para claridad
- Extraer magic numbers a constantes nombradas
- Simplificar nested logic

**Antes**:
```zig
// ❌ While menos claro
var i: usize = 0;
while (i < items.len) : (i += 1) {
    // process items[i]
}
```

**Después**:
```zig
// ✅ For más claro para iterar
for (items) |item| {
    // process item
}

// O con índice:
for (items, 0..) |item, i| {
    // process item at index i
}
```

---

### 4. **Only one obvious way to do things**
✅ **Aplicado**:
- Una forma de crear nodos: `Node.createChar()`, `Node.createCharRange()`
- Una forma de emitir bytecode: `writer.emit1()`, `writer.emit2()`
- Convenciones consistentes

⚠️ **Revisar**:
- Alternation tiene múltiples implementaciones (a arreglar)
- Algunas operaciones tienen paths redundantes

---

### 5. **Runtime crashes are better than bugs**
✅ **Aplicado**:
- `unreachable` para casos imposibles
- Panics explícitos en lugar de silenciar errores
- No ignoramos errores

**Ejemplo**:
```zig
// ✅ Crash explícito mejor que bug silencioso
switch (opcode) {
    .CHAR32 => // handle,
    .CHAR => // handle,
    else => unreachable, // Nunca debería pasar
}
```

---

### 6. **Compile errors are better than runtime crashes**
✅ **Aplicado**:
- Error types explícitos: `CodegenError`, `ParseError`
- Type safety estricto
- No casts implícitos

**Ejemplo**:
```zig
// ✅ Error en compile time
fn generateChar(self: *Self, node: *Node) CodegenError!void {
    // TypeScript permitiría pasar cualquier tipo
    // Zig requiere exactamente *Node
}
```

---

### 7. **Incremental improvements**
✅ **Aplicado**:
- Desarrollo por fases (1-6 completadas)
- Tests incrementales (285/285)
- Features agregadas sin romper existentes

📝 **Estrategia**:
- Pequeños commits atómicos
- Tests antes de features
- Backward compatibility cuando posible

---

### 8. **Avoid local maximums**
🔄 **En revisión**:

**Posibles local maximums en el proyecto**:
- Usar alternation para case-insensitive (funciona pero subóptimo)
- Recursive matcher simple (funciona pero puede ser más eficiente)

**Plan**:
- No optimizar prematuramente
- Primero corrección, luego optimización
- Medir antes de optimizar

---

### 9. **Reduce the amount one must remember**
✅ **Aplicado**:
- API simple: `Regex.compile()`, `re.test_()`, `re.find()`
- Convenciones consistentes de nombres
- Estructura predecible del código

🔄 **Mejoras**:
- Consolidar patrones repetidos
- Reducir parámetros en funciones complejas
- Usar defaults razonables

**Ejemplo**:
```zig
// ✅ Simple, no hay que recordar mucho
var re = try Regex.compile(allocator, "pattern");
const matched = try re.test_("input");

// Opciones solo cuando se necesitan
var re = try Regex.compileWithOptions(allocator, "pattern", .{
    .case_insensitive = true,
});
```

---

### 10. **Focus on code rather than style**
✅ **Aplicado**:
- No hay linter enforcing estilos arbitrarios
- Formato estándar con `zig fmt`
- Pragmático sobre dogmático

📝 **Regla**: Si `zig fmt` lo acepta, es válido.

---

### 11. **Resource allocation may fail; resource deallocation must succeed**
✅ **Aplicado**:
- Todas las allocations retornan `error.OutOfMemory`
- `defer` para garantizar cleanup
- `.deinit()` nunca falla

**Ejemplo**:
```zig
// ✅ Allocation puede fallar
const node = try allocator.create(Node);
errdefer allocator.destroy(node); // Cleanup si falla después

// ✅ Deallocation siempre exitosa
pub fn deinit(self: *Node) void {
    // Nunca retorna error
    self.allocator.destroy(self);
}
```

---

### 12. **Memory is a resource**
✅ **Aplicado**:
- Allocator explícito en todas partes
- `defer` para cleanup automático
- No leaks: 285/285 tests pasan sin leaks

**Patrón en todo el código**:
```zig
var re = try Regex.compile(allocator, "pattern");
defer re.deinit(); // Siempre cleanup

const result = try re.find("input");
defer if (result) |r| r.deinit(); // Cleanup condicional
```

---

### 13. **Together we serve the users**
✅ **Aplicado**:
- Error messages claros
- API intuitiva
- Documentación completa

🔄 **Mejoras**:
- Más ejemplos en docs
- Mejor error reporting
- Performance benchmarks

---

## Checklist de Mejoras Zig Zen

### 🔄 Conversión while → for
- [ ] `lexer.zig`: Convertir loops donde sea apropiado
- [ ] `parser.zig`: Revisar loops de parsing
- [ ] `generator.zig`: Simplificar loops
- [ ] `recursive_matcher.zig`: Modernizar loops
- [ ] `writer.zig`: Revisar loops de bytecode

### 🔄 Comunicación de Intent
- [ ] Renombrar funciones ambiguas
- [ ] Agregar docs a funciones complejas
- [ ] Extraer magic numbers a constantes

### 🔄 Edge Cases
- [ ] Documentar todos los edge cases conocidos
- [ ] Tests específicos para edge cases
- [ ] Fix alternation bug (edge case no manejado)

### 🔄 Simplificación
- [ ] Reducir nesting en funciones complejas
- [ ] Consolidar código duplicado
- [ ] Simplificar lógica de matching

---

## Métricas de Adherencia al Zig Zen

| Principio | Score | Notas |
|-----------|-------|-------|
| 1. Intent preciso | 8/10 | Buenos nombres, necesita más docs |
| 2. Edge cases | 7/10 | Bien manejados, algunos pendientes |
| 3. Legibilidad | 7/10 | Puede mejorar con for loops |
| 4. Una forma obvia | 8/10 | Consistente, algunos duplicados |
| 5. Crash > bugs | 9/10 | Excelente uso de unreachable |
| 6. Compile errors | 10/10 | Perfect type safety |
| 7. Incremental | 10/10 | Excelente progreso por fases |
| 8. No local max | 7/10 | Algunos subóptimos conocidos |
| 9. Poca memoria | 8/10 | API simple, puede simplificar |
| 10. Code > style | 10/10 | Pragmático |
| 11. Dealloc succeed | 10/10 | Perfect error handling |
| 12. Memory resource | 10/10 | Allocator explícito siempre |
| 13. Servir usuarios | 8/10 | Buena API, necesita más docs |

**Score Total**: 112/130 (86%)

---

## Plan de Acción

### Inmediato (antes de Fase A)
1. ✅ Convertir `while` a `for` donde sea apropiado
2. ✅ Extraer magic numbers a constantes
3. ✅ Documentar funciones complejas
4. ✅ Revisar nombres de funciones

### Fase A (con mejoras Zen)
5. Fix alternation (edge case matter)
6. Implementar CHAR_CLASS_INV (one obvious way)
7. ReDoS protection (runtime crashes > bugs)

---

**Última actualización**: 2025-12-02
**Objetivo**: 95%+ adherencia al Zig Zen
