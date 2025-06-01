const functions = require("firebase-functions");
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp();

/**
 * Extrai a hora e os minutos de `timeSource` e aplica na mesma data
 * de `baseDate`.
 *
 * @param {Date} baseDate - A data base.
 * @param {string|Date} timeSource - A hora programada.
 * @return {Date} Um novo objeto Date com hora ajustada.
 */
function extractTimeAsDate(baseDate, timeSource) {
  const date = new Date(timeSource);
  const h = date.getUTCHours();
  const m = date.getUTCMinutes();

  return new Date(
      Date.UTC(
          baseDate.getUTCFullYear(),
          baseDate.getUTCMonth(),
          baseDate.getUTCDate(),
          h,
          m));
}

/**
 * Verifica se os remédios dos usuários foram tomados no horário,
 * comparando o horário agendado com o horário da última abertura do app.
 *
 * Atualiza o status de cada remédio para "on-time" ou "off-time".
 *
 * Endpoint HTTP para execução manual/testes locais.
 */
exports.checkMedicationStatus = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.database();
    const userRef = db.ref("user_test");
    const userSnapshot = await userRef.once("value");
    const user = userSnapshot.val();

    if (!user) {
      res.status(200).send("Nenhum usuário encontrado.");
      return;
    }

    const lastOpenTs = user.last_open;
    const remedios = user.remedios;

    if (!lastOpenTs || !remedios) {
      res.status(200).send("Sem informações de remédios ou último acesso.");
      return;
    }

    const lastOpen = new Date(lastOpenTs);

    for (const remId in remedios) {
      if (Object.prototype.hasOwnProperty.call(remedios, remId)) {
        const rem = remedios[remId];
        if (!rem.scheduled_time) continue;

        const scheduledTimeAdjusted = extractTimeAsDate(
            lastOpen,
            rem.scheduled_time);
        const diff = Math.abs(scheduledTimeAdjusted - lastOpen);
        const isOnTime = diff <= 10 * 60 * 1000;

        const novoStatus = isOnTime ? "on-time" : "off-time";

        if (rem.status !== novoStatus && rem.status === "off-time") {
          await db.ref(`user_test/remedios/${remId}/status`).set(novoStatus);
        }
      }
    }

    console.log("Verificação de status concluída com sucesso.");
    res.status(200).send("Verificação de status concluída com sucesso.");
  } catch (error) {
    console.error("Erro ao verificar status de medicamentos:", error);
    res.status(500).send("Erro interno do servidor.");
  }
});