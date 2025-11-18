# Informe de Análisis de Amenazas — KipuBankV3

## 1. Breve descripción general

KipuBankV3 es un contrato inteligente tipo "bóveda bancaria" que permite a usuarios depositar y retirar la moneda nativa de la cadena (ETH). Cada usuario tiene un saldo individual registrado en el contrato y el sistema aplica dos límites clave:

- **bankCap**: tope global de depósitos que el contrato puede aceptar (establecido en el despliegue).
- **withdrawLimit**: límite por retiro por transacción (definido como `immutable`).

Principales características de la lógica del contrato:

- **Depósitos**: Los usuarios pueden enviar ETH mediante una función `external payable` (por ejemplo `deposit()`), y posiblemente también a través de `receive()` o `fallback()`. Antes de aceptar un depósito, el contrato verifica que el nuevo total no exceda `bankCap`. Si la verificación pasa, el saldo del usuario y contadores (depósitos totales y por usuario) se actualizan y se emite un evento `Deposit`.

- **Retiros**: Los usuarios llaman a `withdraw(uint256 amount)` para retirar ETH de su bóveda personal. La función valida que `amount` sea mayor que cero, que no supere el `withdrawLimit` por transacción y que el usuario tenga saldo suficiente. Luego aplica el patrón **checks → effects → interactions**: resta el saldo antes de realizar la transferencia, actualiza contadores y finalmente realiza un envío seguro (usualmente via `call`). Si la transferencia falla, la operación revierte con un error personalizado.

- **Contadores y métricas**: El contrato mantiene variables de estado públicas o privadas para llevar conteo del número de depósitos y retiros globales y por usuario, además del `totalDeposited` o similar para saber cuánto ETH está retenido.

- **Errores y eventos**: Emplea errores personalizados (por ejemplo `BankCapExceeded`, `InsufficientBalance`, `WithdrawLimitExceeded`, `TransferFailed`, `ZeroAmount`) para revertir con mensajes de bajo coste en gas y emitir eventos (`Deposit`, `Withdraw`) en operaciones exitosas.

- **Protecciones básicas**: Puede incluir un guardia simple contra reentrancy (un `_status` con `nonReentrant`), y modificadores para validar condiciones comunes (por ejemplo `amountNonZero`).

- **Funciones vistas y privadas**: Tiene al menos una función `external view` (por ejemplo `getBalance(address)` o `remainingBankCap()`), y una función `_safeSend(...)` privada que encapsula la lógica de transferencia.

---

## 2. Evaluación de la madurez del protocolo

A continuación se evalúa el nivel de madurez de **KipuBankV3** y se identifican debilidades, vacíos y pasos concretos para avanzar hacia un estado de producción/entrega maduro.

---

### 2.1 Cobertura de pruebas

**Estado estimado actual**
- No se observa una suite de tests completa en el repositorio público (faltan archivos `test/` o están vacíos).
- No hay evidencia de pruebas automatizadas ejecutándose en CI (GitHub Actions u otro).

**Riesgos**
- Cambios en el contrato pueden introducir regresiones no detectadas.
- Casos límite (overflow lógico, reentrancy, edge-cases de `receive()`/`fallback()`) no verificados.

**Recomendaciones prácticas**
1. Implementar tests unitarios con Hardhat + Mocha/Chai (o Foundry si prefieres). Cobertura mínima propuesta:
   - Depósitos: éxito, exceso de `bankCap`, `msg.value = 0`.
   - Retiros: éxito, `withdrawLimit` excedido, saldo insuficiente.
   - Contadores y `totalDeposited`: coherencia tras múltiples operaciones.
   - `receive()` / `fallback()` — que se comporten idénticamente a `deposit()`.
   - Transferencia fallida simulada (uso de contrato malicioso que consume gas en fallback).
   - Reentrancy test: contrato atacante que intenta reentrar.
2. Añadir pruebas de propiedades/invariantes (p. ej. usando fuzzing en Foundry) para validar que `totalDeposited == sum(balances)` siempre.
3. Integrar test suite en CI (GitHub Actions) para ejecución automática en cada PR.

---

### 2.2 Métodos de prueba

**Estado estimado actual**
- Ausencia de estrategia formal de pruebas.

**Recomendaciones**
- **Unit tests**: cubrir funciones individuales y condiciones de borde.
- **Integration tests**: simular flujos (varios usuarios depositan y retiran, múltiples txs concurrentes).
- **Property-based tests / Fuzzing**: validar invariantes contables bajo entradas aleatorias (Foundry/Forge o Echidna).
- **Static analysis**: ejecutar Slither, Solhint, MythX o similar como parte del pipeline.
- **Gas regression tests**: medir consumo de gas para funciones críticas y detectar regresiones.
- **Test de ataque (adversarial tests)**:
  - Reentrancy attacker contract.
  - Forzar situaciones de transferencia fallida (contrato que revierte en `receive()`).
  - Simular límite de `bankCap` con múltiples transacciones paralelas (race conditions en tests locales).
- **Auditoría externa**: al alcanzar estabilidad, pasar a revisión externa (contratación de auditor o bounty).

---

### 2.3 Documentación

**Estado estimado actual**
- README inicial presente, pero puede carecer de:
  - Especificaciones formales (invariantes y pre/post condiciones).
  - Ejemplos de interacción paso a paso.
  - Detalle de eventos y errores.
  - Guía de despliegue y verificación (comandos `hardhat verify`, variables env).
  - Changelog y roadmap.

**Recomendaciones**
1. Documentación técnica en la raíz:
   - `README.md` completo (despliegue, verificación, interacción).
   - `CONTRIBUTING.md` con normas de contribución, formato de commits y estilo.
   - `SECURITY.md` con política de divulgación responsable y direcciones de contacto.
2. Comentarios NatSpec exhaustivos en el contrato (cada función, evento y error).
3. Especificación de invariantes en `docs/invariants.md` (ej. `totalDeposited == sum(balances)`).
4. Ejemplos de uso: scripts `scripts/` para depositar, retirar y consultar, y mostrar salidas esperadas.
5. Registrar contratos desplegados (dirección, red, txHash) en `DEPLOYMENTS.md`.

---

### 2.4 Roles y poderes de los actores del protocolo

**Estado estimado actual**
- KipuBankV3 parece ser *permissionless* en cuanto a depósitos y retiros: cualquier dirección puede interactuar.
- No se aprecia un rol administrador ni poderes especiales (pausar, actualizar parámetros, rescate). Esto reduce superficie de control centralizado pero también elimina posibilidades de mitigación en emergencias.

**Riesgos**
- Sin un mecanismo de pausa o timelock no hay forma de mitigar una vulnerabilidad crítica post-deploy.
- Si se añade un admin con poderes, debe definirse claramente para evitar riesgos de custodia/escape de fondos.

**Recomendaciones**
1. Decidir modelo de gobernanza desde ya:
   - **Sin admin (preferible para demos/auditorías educativas)**: mantener inmutabilidad y ausencia de poderes especiales.
   - **Con admin/guardian**: implementar `Ownable` + `Pausable`, con controles mínimos (pausar retiros o depósitos).
2. Si se añade admin:
   - Registrar roles y poderes en la documentación (quién, cuándo, cómo).
   - Usar multisig (Gnosis Safe) para operaciones administrativas críticas (cambios de parámetros, extracción en emergencias).
   - Registrar auditoría y pruebas para las funciones administrativas (pausar/despausar).
3. Implementar **time-lock** (si se cambia parámetros críticos) para dar ventana de revisión pública.

---

### 2.5 Invariantes

**Invariantes críticas a mantener**
1. `totalDeposited == sum(balances)` — Invariante contable principal. Si se rompe, hay inconsistencia entre fondos almacenados y saldos reportados.
2. `totalDeposited <= bankCap` — Cap global nunca supera el límite establecido.
3. `balances[addr] >= 0` y nunca underflow (en Solidity ^0.8 el underflow revierte, pero la lógica debería protegerlo).
4. `withdraw` solo reduce `balances[msg.sender]` y el efectivo transferido debe provenir exclusivamente del `balance` del usuario.
5. Eventos `Deposit`/`Withdraw` deben reflejar valores reales (cantidad y nuevo balance) para trazabilidad.

**Checks recomendados para asegurar invariantes**
- En tests, después de cualquier secuencia de operaciones aleatorias comprobar globalmente:
  - sumar todos los `balances` leídos y comparar con `totalDeposited`.
  - verificar `totalDeposited <= bankCap`.
- En funciones críticas, mantener checks-effects-interactions y usar un reentrancy guard.
- Evitar rutas de código que envíen ETH sin ajustar `totalDeposited` o `balances` (ej.: funciones administrativas que rescaten fondos).

---

## 3. Vectores de ataque y modelo de amenazas

A continuación se identifican las principales superficies de ataque relevantes para el sistema, agrupadas según su naturaleza técnica y económica:

### 3.1 Errores en la lógica de negocio del contrato inteligente

**(A1) Inconsistencias en el flujo de validación**  
Si el contrato no valida correctamente los estados internos (ej.: compra de tickets, generación de números, o distribución de premios), un atacante podría explotar transiciones inválidas para forzar pagos indebidos, evitar restricciones o eludir costos de participación.

**(A2) Manipulación del ciclo de la lotería**  
Un fallo en la lógica que controla la apertura, cierre o liquidación de los sorteos podría permitir:  
- Cerrar sorteos prematuramente,  
- Reclamar ganancias antes de la verificación,  
- O reabrir rondas usando estados ya calculados.  

Esto comprometería la integridad del juego.

**(A3) Generación de números pseudoaleatorios débil**  
Si la fuente de aleatoriedad no está correctamente asegurada (ej. VRF mal implementado o validado), un atacante podría predecir resultados y comprar tickets estratégicos, destruyendo por completo la equidad del sistema.

---

### 3.2 Uso indebido o abuso de supuestos del protocolo

**(B1) Supuestos incorrectos sobre el comportamiento del usuario**  
Un protocolo que asume buena fe podría permitir:  
- Reclamaciones repetidas del mismo premio,  
- Ejecución de llamadas desde contratos proxy maliciosos,  
- Manipulación de funciones destinadas a usuarios externos.

**(B2) Abuso de mecanismos de reembolso o incentivos**  
Si existen reembolsos por transacciones fallidas o costos parcialmente cubiertos por el protocolo, un atacante podría provocar fallos deliberados para obtener retornos positivos o reducir sus costos de entrada.

**(B3) Aprovechamiento del orden de transacciones (MEV)**  
Validadores o atacantes MEV-capable podrían reordenar transacciones para posicionarse primero tras observar compras de tickets potencialmente ganadoras.

---

### 3.3 Estrategias económicas / exploitativas

**(C1) Ataques de “griefing” para inflar costos operativos**  
Un atacante podría saturar funciones clave baratas (ej. compra mínima de tickets) para aumentar el costo del gas del resto de usuarios, degradando la experiencia y afectando la participación.

**(C2) Acumulación estratégica de liquidez en el pozo de premios**  
Un adversario puede influir económicamente en el juego comprando muchos tickets justo antes del cierre para “asegurar” probabilidades superiores, rompiendo los supuestos del modelo económico.

**(C3) Sybil attacks**  
La creación masiva de identidades para multiplicar oportunidades o reclamar bonificaciones destinadas a nuevos usuarios.

---

### 3.4 Problemas de permisos o configuración de control de acceso

**(D1) Roles administrativos demasiado amplios**  
Si el contrato otorga privilegios como modificar parámetros críticos, alterar premios o reiniciar ciclos sin restricciones estrictas, un atacante que comprometa esa cuenta obtiene control total.

**(D2) Falta de separación entre funciones de usuario y funciones del sistema**  
Funciones que deberían ser internas (ej. distribución de premios, actualización de estados) expuestas públicamente pueden ser invocadas por actores maliciosos.

**(D3) Configuración débil del ownership**  
Uso de `msg.sender` sin protección adicional, transferencia de propiedad insegura o falta de mecanismos como `onlyOwner`, `AccessControl` o multisig, abren riesgos de toma de control del contrato.

---

## 4. Especificación de invariantes

Los siguientes invariantes representan condiciones críticas que **siempre** deben mantenerse en el protocolo, sin importar el flujo, el estado del sistema o el orden de ejecución de las transacciones. Su violación implica un fallo severo en la seguridad o integridad del juego.

### 4.1 Invariante de conservación del pozo de premios  
**(I1) El monto total almacenado en el pozo nunca puede ser negativo ni disminuir sin una operación válida previamente definida.**  
Esto implica:  
- Nunca debe haber transferencias de salida no autorizadas.  
- El pozo solo cambia por: compra de tickets, distribución final o retiro administrativo permitido.  
- No puede haber "creación" o "desaparición" de fondos.

### 4.2 Invariante de unicidad y cierre de sorteos  
**(I2) Un sorteo no puede avanzar a un estado siguiente sin haber completado correctamente el estado previo.**  
Es decir:  
- No se puede distribuir premios sin haber generado el número ganador.  
- No se puede generar número ganador sin cerrar el período de compra de tickets.  
- No se puede abrir un nuevo sorteo mientras el anterior esté pendiente de liquidación.

### 4.3 Invariante de inmutabilidad de tickets  
**(I3) Un ticket comprado nunca puede alterarse, invalidarse o duplicarse después de su emisión.**  
Esto garantiza que:  
- Los datos del ticket (participante, números, timestamp, identificador) permanecen inmutables.  
- Ningún actor (ni usuario ni administrador) puede modificar tickets existentes.  
- No puede existir dos tickets con el mismo ID en un mismo sorteo.

### 4.4 Invariante de distribución justa  
**(I4) Los premios solo pueden asignarse a tickets válidos que coincidan con el número ganador del sorteo correspondiente.**  
Esto implica:  
- No pueden asignarse premios a tickets de otros sorteos.  
- Un ticket debe cumplir todos los requisitos (estado, pago, registro válido).  
- La verificación de ganadores siempre debe ser determinista.

### 4.5 Invariante de control de acceso  
**(I5) Ninguna función administrativa puede ejecutarse por cuentas no autorizadas.**  
Esto incluye:  
- No permitir que funciones de mantenimiento, parámetros económicos o reinicio del sistema se ejecuten desde direcciones no configuradas.  
- Control de acceso consistente en todo el ciclo del contrato.  
- El owner o multisig nunca debe perder capacidad de recuperación segura.

---

## 5. Impacto de las violaciones de invariantes


La ruptura de cualquiera de los invariantes definidos compromete directamente la seguridad, integridad y confiabilidad del protocolo. A continuación se detalla el impacto asociado a cada invariante:


### 5.1 Impacto al violar el Invariante de conservación del pozo de premios (I1)
Si los fondos del pozo disminuyen sin justificación o aparecen inconsistencias, el protocolo enfrenta:
- **Pérdida directa de fondos** pertenecientes a los participantes.
- **Imposibilidad de distribuir premios correctamente**, afectando la credibilidad del sorteo.
- **Vector de ataque crítico** que permite extracción indebida de valor (rug-pull o drain del contrato).
- **Riesgo legal y reputacional severo**, al fallar en la custodia de fondos.


Este tipo de violación se considera de **máxima gravedad**.


### 5.2 Impacto al violar el Invariante de unicidad y cierre correcto de sorteos (I2)
Permitir que un sorteo avance sin completar un estado previo puede causar:
- **Condiciones de carrera** donde algunos usuarios no puedan participar o reclamen prematuramente.
- **Inconsistencias en la generación del número ganador**, afectando la equidad del sistema.
- **Doble asignación o pérdida de premios** por existencia de estados superpuestos.
- **Desincronización total del sistema**, donde ningún sorteo tiene estados confiables.


Su impacto es **alto** ya que compromete la lógica del producto y la confianza del usuario.


### 5.3 Impacto al violar el Invariante de inmutabilidad de tickets (I3)
Modificar o duplicar tickets después de su creación permitiría:
- **Fraude directo**, creando tickets que coincidan con el número ganador.
- **Anulación de tickets legítimos**, perjudicando a usuarios reales.
- **Manipulación interna o externa del sistema**.
- **Divergencias entre los datos del contrato y los reclamos de usuarios**.


El impacto es **crítico**, ya que destruye todo el modelo de equidad del sorteo.


### 5.4 Impacto al violar el Invariante de distribución justa (I4)
Asignar premios a tickets no válidos o incorrectos produciría:
- **Pérdida financiera para los jugadores legítimos**.
- **Posibilidad de manipulación por insiders**.
- **Desconfianza en la determinación del ganador**.
- **Riesgo de explotación económica recurrente**.


Se clasifica como un impacto **alto a crítico** dependiendo del modo de explotación.


### 5.5 Impacto al violar el Invariante de control de acceso (I5)
Permitir que funciones administrativas sean ejecutadas por actores no autorizados genera:
- **Toma de control total del protocolo** por un atacante.
- **Manipulación de parámetros económicos o cierre del sistema**.
- **Extracción de fondos del pozo**.
- **Despliegue de funciones maliciosas o bloqueo del contrato**.


La violación de este invariante representa uno de los peores escenarios imaginables y su impacto es **crítico absoluto**.

---

## 6. Recomendaciones para Validar los Invariantes

Las siguientes recomendaciones permiten asegurar que los invariantes definidos se mantengan en cualquier escenario, fortaleciendo la seguridad y previsibilidad del protocolo.

### 6.1 Validación del Invariante de conservación del pozo de premios (I1)
**Recomendaciones:**
- Implementar pruebas unitarias y de propiedad (property-based testing) que verifiquen que los fondos del contrato solo cambian mediante rutas autorizadas.
- Utilizar `assert` internos para confirmar que cualquier modificación en los saldos es coherente con las reglas del protocolo.
- Registrar eventos detallados para cada operación que modifique balances.
- Prohibir operaciones económicas que dependan de supuestos externos no garantizados.

### 6.2 Validación del Invariante de unicidad y cierre correcto de sorteos (I2)
**Recomendaciones:**
- Incorporar pruebas de máquina de estados que verifiquen la transición correcta entre fases del sorteo.
- Aplicar modificadores que impidan ejecutar funciones en un estado incorrecto.
- Diseñar pruebas que simulen múltiples ciclos completos del sorteo para detectar rutas inválidas.
- Emplear fuzzing para destruir flujos de estado y confirmar que el contrato no permite saltar estados obligatorios.

### 6.3 Validación del Invariante de inmutabilidad de tickets (I3)
**Recomendaciones:**
- Escribir pruebas que intenten alterar tickets después de haber sido creados.
- Evitar funciones internas o externas que reescriban estructuras ya definidas.
- Garantizar que las rutas internas no permitan modificar identificadores de tickets.
- Utilizar pruebas de colisión y fuzzing para detectar alteraciones inesperadas.

### 6.4 Validación del Invariante de distribución justa (I4)
**Recomendaciones:**
- Ejecutar simulaciones de múltiples participantes y verificar que solo tickets válidos pueden ganar.
- Realizar asserts que confirmen que el ticket ganador pertenece al conjunto correcto.
- Verificar mediante pruebas automatizadas que los fondos distribuidos coinciden con el algoritmo de reparto.
- Añadir pruebas adversariales que intenten explotar sesgos o manipulaciones.

### 6.5 Validación del Invariante de control de acceso (I5)
**Recomendaciones:**
- Crear pruebas unitarias que aseguren que ninguna función administrativa es accesible sin permisos.
- Aplicar fuzzing sobre permisos para intentar llamadas maliciosas desde direcciones arbitrarias.
- Validar que los modificadores de acceso bloquean correctamente actores no autorizados.
- Mantener funciones críticas bajo roles claramente definidos (`onlyOwner`, AccessControl, etc.).

---

## 7. Conclusión y Próximos Pasos

El análisis realizado evidencia que el protocolo avanza en una dirección correcta, pero aún requiere fortalecer varios aspectos fundamentales antes de considerarse maduro y listo para una auditoría formal. Si bien la lógica principal es clara y el flujo operativo es consistente, el sistema aún presenta áreas que deben evolucionar para garantizar seguridad, resiliencia y verificabilidad matemática.

### 7.1 Conclusión General
KipuBankV3 demuestra una arquitectura simple y comprensible, un buen punto de partida para un protocolo financiero de depósito/retiro. Aun así, para alcanzar un nivel de robustez alineado con estándares profesionales de DeFi, es imprescindible mejorar la calidad de las pruebas, reforzar los mecanismos de control de acceso, definir propiedades formales del sistema y documentar completamente la lógica interna y sus supuestos.

Con estos ajustes, el protocolo no solo estaría en mejores condiciones para una auditoría externa, sino también para su crecimiento y mantenimiento a largo plazo.

### 7.2 Próximos Pasos Recomendados

#### 🔒 Seguridad y control de acceso
- **Revisar y fortalecer los permisos** de funciones críticas, evitando cualquier vector indirecto de modificación del estado.
- Evaluar la necesidad de introducir un sistema de roles más detallado si se planea expandir el protocolo.

#### 🧪 Pruebas y verificación
- **Incrementar la cobertura de pruebas unitarias (>95%)** especialmente en casos límite.
- Agregar **fuzzing automatizado** para detectar comportamientos inesperados.
- Incluir **pruebas de propiedad** enfocadas en invariantes clave como balances, límites y consistencia contable.

#### 📘 Documentación
- Completar documentación técnica en formato estándar:  
  - Descripción de funciones  
  - Flujo de estados  
  - Supuestos del protocolo  
  - Errores esperados y comportamiento en casos borde  

#### 🔍 Revisión de invariantes
- Añadir comentarios en el código indicando explícitamente los invariantes asociados a cada área crítica.
- Implementar asserts internos donde sea seguro hacerlo para reforzar la defensa ante violaciones lógicas.

#### 🛠️ Hardening del contrato
- Revisar posibles dependencias de gas, limitaciones del `call`, y situaciones donde una transferencia falle.
- Considerar mecanismos adicionales anti-reentrancy si se agregan nuevas interacciones económicas.

#### 🧭 Preparación para Auditoría
- Generar un **Threat Model Diagram** (diagrama de modelo de amenazas).
- Preparar un **mapa completo de funciones**, detallando qué puede romperse y por qué.
- Documentar decisiones de diseño y por qué se eligieron ciertos patrones de seguridad.

---

En conjunto, estos pasos consolidan la integridad del protocolo, aumentan la confianza en su funcionamiento y proporcionan una base sólida para enfrentar una auditoría profesional. Una vez ejecutadas estas mejoras, KipuBankV3 estará listo para una revisión exhaustiva y posterior despliegue en un entorno más amplio.
