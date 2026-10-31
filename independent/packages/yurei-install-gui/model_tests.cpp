#include "model.h"
#include <QtTest>

class ModelTests : public QObject {
    Q_OBJECT
private:
    QJsonObject disk() {
        return {{"path", "/dev/vda"}, {"type", "disk"}, {"model", "Test disk"},
                {"ro", false}, {"size", 68719476736.0}, {"maj:min", "252:0"}, {"mountpoints", QJsonArray{QJsonValue::Null}}};
    }
    QByteArray inventory(const QJsonObject &node) {
        return QJsonDocument(QJsonObject{{"blockdevices", QJsonArray{node}}}).toJson();
    }
    InstallRequest request() { return {"yurei", "yurei-pc", "test-password", "test-password", "root-password", "root-password"}; }
private slots:
    void acceptsBlankWritableWholeDisk() { QCOMPARE(eligibleDisks(inventory(disk()), 1).size(), 1); }
    void rejectsMountedChildAndLiveMedium() {
        auto node = disk();
        node.insert("children", QJsonArray{QJsonObject{{"mountpoints", QJsonArray{"/run/live/medium"}}}});
        QVERIFY(eligibleDisks(inventory(node), 1).isEmpty());
    }
    void rejectsReadOnlyDisk() { auto node = disk(); node.insert("ro", true); QVERIFY(eligibleDisks(inventory(node), 1).isEmpty()); }
    void rejectsUnknownMountState() { auto node = disk(); node.remove("mountpoints"); QVERIFY(eligibleDisks(inventory(node), 1).isEmpty()); }
    void rejectsPartitionsAndSmallDisks() {
        auto node = disk(); node.insert("type", "part"); QVERIFY(eligibleDisks(inventory(node), 1).isEmpty());
        QVERIFY(eligibleDisks(inventory(disk()), 100000000000ULL).isEmpty());
    }
    void rejectsMalformedInventory() { QString error; QVERIFY(eligibleDisks("not json", 1, &error).isEmpty()); QVERIFY(!error.isEmpty()); }
    void validatesAccountAndPasswords() {
        auto data = request(); QVERIFY(data.validationError().isEmpty());
        data.user = "root"; QVERIFY(!data.validationError().isEmpty());
        data = request(); data.repeat = "different"; QVERIFY(!data.validationError().isEmpty());
        data = request(); data.password = data.repeat = "line\nbreak"; QVERIFY(!data.validationError().isEmpty());
    }
    void requiresExactConfirmationAndLiveMode() {
        const Disk target{"/dev/vda", "Test", "252:0", 68719476736ULL};
        QVERIFY(canInstall(request(), target, true, false, true, "ERASE /dev/vda"));
        QVERIFY(!canInstall(request(), target, true, true, true, "ERASE /dev/vda"));
        QVERIFY(!canInstall(request(), target, false, false, true, "ERASE /dev/vda"));
        QVERIFY(!canInstall(request(), target, true, false, false, "ERASE /dev/vda"));
        QVERIFY(!canInstall(request(), target, true, false, true, "ERASE /dev/vdb"));
    }
    void passwordsNeverEnterArguments() {
        const auto data = request();
        const auto args = backendArguments(data, {"/dev/vda", "Test", "252:0", 68719476736ULL});
        QVERIFY(args.contains("--passwords-stdin"));
        QVERIFY(!args.join(' ').contains(data.password)); QVERIFY(!args.join(' ').contains(data.rootPassword));
        QVERIFY(args.contains("--expected-disk-device")); QVERIFY(args.contains("--expected-disk-bytes"));
    }
};
QTEST_MAIN(ModelTests)
#include "model_tests.moc"
