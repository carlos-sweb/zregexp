# zregexp - Motor Moderno de Expresiones Regulares para Zig

[![Licencia: MIT](https://img.shields.io/badge/Licencia-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-304%2F304-brightgreen)](#)
[![Zig](https://img.shields.io/badge/zig-0.13.0-orange)](https://ziglang.org/)

[<ì<ç English Version](README.md)

Un motor de expresiones regulares potente y rico en características, escrito en Zig con sintaxis similar a JavaScript y protección contra ReDoS.

## ( Características

- **=€ Alto Rendimiento**: Máquina virtual basada en bytecode con ejecución optimizada
- **=á Protección contra ReDoS**: Límites integrados de profundidad de recursión y pasos para prevenir backtracking catastrófico
- **=Ý Sintaxis Compatible con JavaScript**: ~70% de compatibilidad con JavaScript RegExp
- **=' Cero Dependencias**: Implementación pura en Zig
- **< Bindings para C/C++**: Integración fácil con proyectos C y C++
- ** Bien Probado**: 304 tests exhaustivos que aseguran confiabilidad

## <¯ Características Soportadas

### Assertions (100% Compatible con JS)
-  `(?=...)` Lookahead positivo
-  `(?!...)` Lookahead negativo
-  `(?<=...)` Lookbehind positivo
-  `(?<!...)` Lookbehind negativo

### Grupos (100% Compatible con JS)
-  `(...)` Grupos de captura
-  `(?:...)` Grupos sin captura
-  `\1` a `\9` Referencias hacia atrás

### Cuantificadores (100% Compatible con JS + Extensiones)
-  `*`, `+`, `?` Cuantificadores básicos
-  `*?`, `+?`, `??` Cuantificadores lazy
-  `{n}`, `{n,}`, `{n,m}` Cuantificadores contados
-  `{n}?`, `{n,}?`, `{n,m}?` Cuantificadores contados lazy
-  `*+`, `++`, `?+` Cuantificadores posesivos (extensión)

### Clases de Caracteres
-  `[abc]`, `[^abc]` Conjuntos de caracteres
-  `[a-z]`, `[A-Z0-9]` Rangos de caracteres
-  `.` Cualquier carácter (excepto nueva línea)
-  `\d`, `\D` Dígitos / no-dígitos
-  `\w`, `\W` Caracteres de palabra / no-palabra
-  `\s`, `\S` Espacios en blanco / no-espacios

### Anclajes
-  `^` Inicio de cadena
-  `$` Fin de cadena
-  `\b` Límite de palabra
-  `\B` No-límite de palabra

## =æ Instalación

### Uso como Librería Zig

Agrega a tu `build.zig.zon`:

```zig
.dependencies = .{
    .zregexp = .{
        .url = "https://github.com/tuusuario/zregexp/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

En tu `build.zig`:

```zig
const zregexp = b.dependency("zregexp", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zregexp", zregexp.module("zregexp"));
```

### Uso como Librería C/C++

Descarga las librerías precompiladas desde [Releases](https://github.com/tuusuario/zregexp/releases):

**Linux/macOS:**
- `libzregexp.so` / `libzregexp.dylib` (librería compartida)
- `libzregexp.a` (librería estática)
- `zregexp.h` (header C)
- `zregexp.hpp` (header C++)

**Windows:**
- `zregexp.dll` (librería dinámica)
- `zregexp.lib` (librería de importación)
- `zregexp.h` (header C)
- `zregexp.hpp` (header C++)

## =€ Inicio Rápido

### Ejemplo en Zig

```zig
const std = @import("std");
const regex = @import("zregexp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Compilar un patrón regex
    var re = try regex.Regex.compile(allocator, "hola (\\w+)");
    defer re.deinit();

    // Buscar una coincidencia
    const result = try re.find("hola mundo");
    if (result) |match| {
        defer match.deinit();

        std.debug.print("Match: {s}\n", .{match.slice()});
        std.debug.print("Grupo 1: {s}\n", .{match.group(1).?});
    }
}
```

### Ejemplo en C

```c
#include "zregexp.h"
#include <stdio.h>

int main(void) {
    // Compilar regex
    ZRegex* re = zregexp_compile("hola (\\w+)", NULL);
    if (!re) {
        fprintf(stderr, "Error al compilar regex\n");
        return 1;
    }

    // Buscar coincidencia
    ZMatch* match = zregexp_find(re, "hola mundo");
    if (match) {
        const char* coincidencia = zregexp_match_slice(match);
        const char* grupo1 = zregexp_match_group(match, 1);

        printf("Match: %s\n", coincidencia);
        printf("Grupo 1: %s\n", grupo1);

        zregexp_match_free(match);
    }

    zregexp_free(re);
    return 0;
}
```

### Ejemplo en C++

```cpp
#include "zregexp.hpp"
#include <iostream>

int main() {
    try {
        // Compilar regex
        auto re = zregexp::Regex::compile("hola (\\w+)");

        // Buscar coincidencia
        auto match = re.find("hola mundo");
        if (match) {
            std::cout << "Match: " << match.slice() << std::endl;
            std::cout << "Grupo 1: " << match.group(1) << std::endl;
        }
    } catch (const zregexp::RegexError& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

## =Ú Documentación de la API

### API de Zig

#### `Regex.compile(allocator, pattern) !Regex`
Compila un patrón regex.

**Parámetros:**
- `allocator`: Asignador de memoria
- `pattern`: Cadena del patrón regex

**Retorna:** Objeto `Regex` compilado

**Ejemplo:**
```zig
var re = try Regex.compile(allocator, "\\d{3}-\\d{3}-\\d{4}");
defer re.deinit();
```

#### `regex.find(input) !?MatchResult`
Encuentra la primera coincidencia en la cadena de entrada.

**Parámetros:**
- `input`: Cadena donde buscar

**Retorna:** `MatchResult` si se encuentra, `null` en caso contrario

#### `regex.findAll(input) !std.ArrayList(MatchResult)`
Encuentra todas las coincidencias en la cadena de entrada.

#### `regex.isMatch(input) !bool`
Prueba si el patrón coincide con la entrada.

#### `regex.replace(input, replacement) ![]const u8`
Reemplaza todas las coincidencias con la cadena de reemplazo.

### API de C

Ver `zregexp.h` para documentación completa de la API.

**Funciones Principales:**
- `ZRegex* zregexp_compile(const char* pattern, ZRegexOptions* options)`
- `ZMatch* zregexp_find(ZRegex* regex, const char* input)`
- `ZMatchList* zregexp_find_all(ZRegex* regex, const char* input)`
- `bool zregexp_is_match(ZRegex* regex, const char* input)`
- `char* zregexp_replace(ZRegex* regex, const char* input, const char* replacement)`
- `void zregexp_free(ZRegex* regex)`
- `void zregexp_match_free(ZMatch* match)`

### API de C++

Ver `zregexp.hpp` para documentación completa de la API.

**Clases Principales:**
- `zregexp::Regex` - Clase principal de regex con semántica RAII
- `zregexp::Match` - Resultado de coincidencia con limpieza automática
- `zregexp::RegexError` - Tipo de excepción para manejo de errores

## =' Compilar desde el Código Fuente

### Prerequisitos
- Zig 0.13.0 o posterior

### Pasos de Compilación

```bash
# Clonar el repositorio
git clone https://github.com/tuusuario/zregexp.git
cd zregexp

# Ejecutar tests
zig build test

# Compilar todas las librerías
zig build

# Compilar para plataformas específicas
zig build -Dtarget=x86_64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-linux
```

Las librerías compiladas estarán en `zig-out/lib/`:
- `libzregexp.so` / `libzregexp.dylib` (compartida)
- `libzregexp.a` (estática)
- `zregexp.dll` / `zregexp.lib` (Windows)

## ¡ Rendimiento

zregexp utiliza una máquina virtual basada en bytecode para matching eficiente de patrones:

- **Compilación Rápida**: Los patrones se compilan a bytecode optimizado
- **Ejecución Eficiente**: Interpretación directa de bytecode con overhead mínimo
- **Protección ReDoS**: Límites configurables previenen backtracking catastrófico
- **Eficiente en Memoria**: Gestión cuidadosa de memoria con arena allocators

### Benchmarks

```
Patrón: \d{3}-\d{3}-\d{4}
Entrada: "Llámame al 555-123-4567"
Tiempo: ~150ns por match

Patrón: (?<=\$)\d+
Entrada: "Precio: $100, $200, $300"
Tiempo: ~200ns por match
```

## =á Seguridad

### Protección contra ReDoS

zregexp incluye protección integrada contra ataques de Denegación de Servicio por Expresiones Regulares (ReDoS):

- **Límite de Profundidad de Recursión**: Por defecto 1000 (configurable)
- **Límite de Pasos**: Por defecto 1,000,000 (configurable)
- **Detección Automática**: Los patrones que exceden los límites fallan gracefully

### Configuración

```zig
const options = regex.CompileOptions{
    .max_recursion_depth = 500,
    .max_steps = 100_000,
    .case_insensitive = true,
};

var re = try regex.Regex.compileWithOptions(allocator, pattern, options);
```

## =Ö Ejemplos de Patrones

### Validación de Email
```zig
const email_pattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}";
```

### Matching de URL
```zig
const url_pattern = "(?:https?://)?(?:www\\.)?[a-zA-Z0-9.-]+\\.[a-z]{2,}(?:/\\S*)?";
```

### Número de Teléfono
```zig
const phone_pattern = "\\+?\\d{1,3}?[-.\\s]?\\(?\\d{1,4}\\)?[-.\\s]?\\d{1,4}[-.\\s]?\\d{1,9}";
```

### Tags HTML
```zig
const html_tag_pattern = "<(\\w+)[^>]*>.*?</\\1>";
```

### Extraer Precios
```zig
const price_pattern = "(?<=\\$)\\d+(?:\\.\\d{2})?";
```

### Validación de Contraseñas
```zig
// Al menos 8 caracteres, 1 mayúscula, 1 minúscula, 1 dígito
const password_pattern = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$";
```

## > Contribuir

¡Las contribuciones son bienvenidas! Por favor, siéntete libre de enviar un Pull Request.

### Configuración de Desarrollo

```bash
# Clonar y compilar
git clone https://github.com/tuusuario/zregexp.git
cd zregexp
zig build test

# Ejecutar tests específicos
zig test src/regex.zig
```

### Estilo de Código
- Seguir las convenciones de la biblioteca estándar de Zig
- Agregar tests para nuevas características
- Actualizar documentación
- Ejecutar `zig fmt` antes de commitear

## =Ä Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## =O Agradecimientos

- Inspirado por JavaScript RegExp y PCRE
- Construido con [Zig](https://ziglang.org/)
- Gracias a todos los contribuidores

## =ì Contacto

- GitHub Issues: [Reportar bugs o solicitar características](https://github.com/tuusuario/zregexp/issues)
- Discussions: [Hacer preguntas y compartir ideas](https://github.com/tuusuario/zregexp/discussions)

## =ú Hoja de Ruta

### Completado 
- [x] Matching básico de caracteres
- [x] Clases y rangos de caracteres
- [x] Cuantificadores (greedy, lazy, possessive)
- [x] Grupos con y sin captura
- [x] Referencias hacia atrás
- [x] Assertions lookahead
- [x] Assertions lookbehind
- [x] Anclajes y límites de palabra
- [x] Protección ReDoS
- [x] Bindings para C/C++

### En Progreso =§
- [ ] Grupos de captura nombrados `(?<nombre>...)`
- [ ] Escapes de propiedades Unicode `\p{...}`
- [ ] Soporte completo UTF-8/UTF-16

### Futuro =.
- [ ] Patrones condicionales `(?(condición)sí|no)`
- [ ] Patrones recursivos
- [ ] Compilación JIT
- [ ] Soporte para target WASM
- [ ] Optimizaciones de rendimiento

## =Ê Estadísticas del Proyecto

- **Líneas de Código**: ~11,000
- **Cantidad de Tests**: 304 tests exhaustivos
- **Tasa de Éxito de Tests**: 100%
- **Compatibilidad JavaScript**: ~70%
- **Plataformas Soportadas**: Linux, macOS, Windows, *BSD
- **Dependencias**: Cero (Zig puro)
- **Lenguaje**: Zig 0.13.0+

## <Æ Comparación de Características

| Característica | zregexp | JavaScript | PCRE2 | RE2 |
|----------------|---------|------------|-------|-----|
| Lookahead |  |  |  |  |
| Lookbehind |  |  |  | L |
| Referencias atrás |  |  |  | L |
| Grupos sin captura |  |  |  |  |
| Cuantificadores lazy |  |  |  |  |
| Cuantificadores posesivos |  | L |  | L |
| Protección ReDoS |  | L | L |  |
| Unicode | =§ |  |  |  |

---

**Hecho con d usando Zig**

**Versión**: 1.0.0
**Estado**: Listo para Producción
**Versión de Zig**: 0.13.0+
