# Guía: Recomendaciones prácticas de implementación y transición híbrida

A partir de los resultados obtenidos en este Trabajo Fin de Máster, se pueden extraer recomendaciones prácticas para una futura transición hacia TLS 1.3 híbrido con criptografía post-cuántica en infraestructuras corporativas reales. Estas recomendaciones se basan en los principales efectos observados durante la campaña experimental: aumento del tamaño del `ClientHello`, incremento del volumen total transmitido, sensibilidad a RTT y pérdida, variación de throughput, consumo de CPU y posible interacción con dispositivos intermedios.

Como ejemplo de aplicación, se considera una infraestructura bancaria compuesta por proxies cloud de navegación segura, como Zscaler, cortafuegos de nueva generación, como Palo Alto Networks, balanceadores F5 y servidores finales. En este tipo de arquitectura, el tráfico TLS no circula únicamente entre cliente y servidor, sino que atraviesa distintos puntos de inspección, terminación, reenvío o control. Por ello, la transición a TLS 1.3 híbrido no debería abordarse como un cambio global inmediato, sino como un proceso progresivo, medido y reversible.

## 1. Inventario criptográfico y protocolario

La primera recomendación es realizar un inventario criptográfico y protocolario de la infraestructura. Deben identificarse los puntos donde se termina, inspecciona o reenvía tráfico TLS: clientes corporativos, proxies Zscaler, firewalls Palo Alto, balanceadores F5 y servidores finales.

Para cada tramo debe verificarse:

- versión de TLS soportada;
- grupos de intercambio de claves permitidos;
- políticas de inspección SSL/TLS;
- perfiles de descifrado;
- reglas de seguridad aplicadas;
- aplicaciones críticas afectadas.

## 2. Validación por tramos

La segunda recomendación es validar la transición por tramos. En una arquitectura bancaria pueden existir varios segmentos TLS diferenciados: cliente-proxy, proxy-destino externo, usuario-aplicación interna, firewall-balanceador y balanceador-servidor final.

Cada tramo puede tener capacidades distintas y debe probarse de forma independiente. No debe asumirse que la compatibilidad del cliente con TLS híbrido implica compatibilidad automática en proxies, cortafuegos, balanceadores o servidores.

## 3. Consideraciones para proxies Zscaler

En proxies cloud como Zscaler, debe comprobarse el comportamiento ante `ClientHello` de mayor tamaño y ante grupos híbridos como `X25519MLKEM768`. La inspección TLS puede terminar la sesión original y generar una nueva conexión hacia el destino, por lo que es necesario verificar si la plataforma permite, bloquea, ignora o modifica la negociación híbrida.

Las métricas relevantes serían:

- errores de handshake;
- resets TCP;
- timeouts;
- degradación de navegación;
- latencia p95/p99;
- comportamiento por categoría de aplicación.

## 4. Consideraciones para cortafuegos Palo Alto

En cortafuegos Palo Alto, la validación debe centrarse en las políticas de inspección SSL/TLS, perfiles de descifrado, App-ID, Threat Prevention y reglas que puedan depender del contenido o estructura inicial del handshake.

Aunque TLS 1.3 híbrido sea protocolariamente válido, el aumento del tamaño del `ClientHello` o la aparición de grupos no habituales puede activar comportamientos restrictivos en dispositivos intermedios. Por ello, deberían realizarse pruebas con descifrado activado y desactivado.

## 5. Consideraciones para balanceadores F5

En balanceadores F5, la transición debe analizarse en los perfiles `client-side` y `server-side`. Si el F5 termina TLS, el impacto del modo híbrido afectará directamente al perfil de entrada. Si además establece una nueva sesión TLS hacia los servidores finales, también será necesario validar el tramo interno.

Deben revisarse especialmente:

- límites de tamaño de handshake;
- compatibilidad de grupos criptográficos;
- consumo de CPU;
- reutilización de sesiones;
- errores TLS;
- comportamiento bajo concurrencia.

## 6. Estrategia de despliegue progresivo

La estrategia recomendada de despliegue es gradual. Primero debería probarse el modo híbrido en laboratorio; después, en preproducción con flujos representativos; posteriormente, en un piloto limitado con usuarios, sedes o aplicaciones de bajo riesgo; y finalmente, en oleadas controladas sobre servicios más críticos.

En todas las fases debe existir un mecanismo de rollback que permita volver rápidamente a negociación clásica si aparecen incompatibilidades o degradaciones relevantes.

## 7. Métricas recomendadas durante la transición

Durante la transición, deberían monitorizarse métricas similares a las utilizadas en este TFM:

- tamaño del `ClientHello`;
- bytes totales transmitidos;
- número de paquetes;
- retransmisiones TCP;
- resets TCP;
- errores TLS;
- latencia CH→SH p95/p99;
- throughput de handshakes;
- CPU en dispositivos que terminan o inspeccionan TLS.

Es especialmente importante no basarse solo en valores medios, ya que los problemas de compatibilidad o degradación suelen aparecer en percentiles altos o en perfiles concretos de red.

## 8. Impacto esperado del modo híbrido

Los resultados del laboratorio muestran que el impacto principal del modo híbrido se concentra en el aumento estructural del `ClientHello`, cercano al +568 %, y en el incremento del volumen total transmitido, alrededor del +53 %.

En una infraestructura bancaria, este crecimiento puede afectar a MSS, segmentación TCP, retransmisiones, inspección TLS y compatibilidad con middleboxes. Por tanto, cualquier piloto debería verificar explícitamente si el `ClientHello` híbrido se transporta en uno o varios segmentos y si ello genera efectos adversos en proxies, cortafuegos o balanceadores.

También debe evaluarse el consumo de CPU en los puntos de terminación TLS. En el laboratorio, el modo híbrido incrementa el consumo del servidor, aunque sin alcanzar saturación sistemática. En una infraestructura real, los puntos más sensibles serían los proxies de salida, balanceadores de entrada, firewalls con descifrado TLS y servidores con alta tasa de conexiones.

Si el incremento de CPU coincide con alta concurrencia o inspección profunda, podría ser necesario ajustar capacidad, limitar el despliegue inicial o segmentar la activación por servicios.

## 9. Fases recomendadas para una transición TLS híbrida

| Fase | Objetivo | Componentes principales | Métricas clave |
|---|---|---|---|
| Inventario | Identificar puntos TLS y capacidades | Zscaler, Palo Alto, F5, servidores | Versiones TLS, perfiles SSL, políticas de inspección |
| Laboratorio | Validar compatibilidad básica | Clientes de prueba, firewall, F5, servidor test | Éxito de handshake, ClientHello, errores TLS |
| Preproducción | Reproducir flujos reales sin impacto productivo | Proxies, firewalls, balanceadores, aplicaciones no críticas | Latencia p95/p99, retransmisiones, throughput, CPU |
| Piloto limitado | Activar TLS híbrido en un alcance reducido | Usuarios, sedes o aplicaciones seleccionadas | Incidencias, resets, timeouts, experiencia de usuario |
| Despliegue progresivo | Ampliar por oleadas controladas | Infraestructura completa por segmentos | Estabilidad, rendimiento, errores, capacidad |
| Operación continua | Mantener supervisión y rollback | Equipos de red, seguridad, SOC y aplicaciones | Alertas TLS, CPU, latencia, compatibilidad |

## 10. Conclusión operativa

En resumen, la transición a TLS 1.3 híbrido en una infraestructura bancaria debe abordarse como un proceso de ingeniería y no como una simple sustitución criptográfica.

Las principales recomendaciones son:

1. Inventariar los puntos TLS.
2. Validar cada tramo de comunicación.
3. Probar explícitamente proxies, firewalls y balanceadores.
4. Monitorizar percentiles altos y errores.
5. Mantener compatibilidad clásica durante la transición.
6. Desplegar progresivamente por servicios o segmentos de bajo riesgo.

De este modo, la adopción de criptografía post-cuántica puede realizarse de forma controlada, reduciendo el riesgo operativo y manteniendo la disponibilidad de los servicios críticos.
