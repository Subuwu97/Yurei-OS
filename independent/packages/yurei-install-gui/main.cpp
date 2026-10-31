#include "model.h"
#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QComboBox>
#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPainter>
#include <QPlainTextEdit>
#include <QProcess>
#include <QProcessEnvironment>
#include <QProgressBar>
#include <QPushButton>
#include <QStackedWidget>
#include <QTimer>
#include <QVBoxLayout>
#ifdef Q_OS_LINUX
#include <unistd.h>
#endif

class Installer : public QWidget {
    bool preview, live = false, running = false;
    int page = 0;
    QVector<Disk> disks;
    QStackedWidget *pages;
    QLabel *notice, *error, *review, *phase, *finished;
    QComboBox *diskChoice;
    QLineEdit *user, *hostname, *password, *repeat, *rootPassword, *rootRepeat, *confirmation;
    QCheckBox *samePassword, *acknowledge;
    QPushButton *back, *next, *close;
    QPlainTextEdit *log;
    QProgressBar *progress;
    QProcess process;
    QByteArray credentials;
    QStringList secrets;
    const QStringList steps = {"Welcome", "Disk", "Account", "Review", "Install", "Finish"};
    QLabel *stepLabel;

    QLabel *text(const QString &value, int size = 15) {
        auto *label = new QLabel(value);
        label->setTextFormat(Qt::PlainText); label->setWordWrap(true);
        label->setStyleSheet(QString("font-size:%1px;").arg(size));
        return label;
    }
    QVBoxLayout *newPage(const QString &title, const QString &body) {
        auto *widget = new QWidget;
        auto *layout = new QVBoxLayout(widget);
        layout->setContentsMargins(0, 16, 0, 8); layout->setSpacing(18);
        layout->addWidget(text(title, 30)); layout->addWidget(text(body));
        pages->addWidget(widget); return layout;
    }
    QLineEdit *field(bool secret = false) {
        auto *input = new QLineEdit; input->setMaxLength(secret ? 256 : 63);
        if (secret) input->setEchoMode(QLineEdit::Password);
        connect(input, &QLineEdit::textChanged, this, [this] { updateButtons(); });
        return input;
    }
    Disk selectedDisk() const {
        const int index = diskChoice->currentIndex();
        return index >= 0 && index < disks.size() ? disks[index] : Disk{};
    }
    InstallRequest request() const {
        return {user->text(), hostname->text(), password->text(), repeat->text(),
                samePassword->isChecked() ? password->text() : rootPassword->text(),
                samePassword->isChecked() ? repeat->text() : rootRepeat->text()};
    }
    QByteArray readOnlyCommand(const QString &program, const QStringList &args) {
        QProcess query; query.start(program, args);
        if (!query.waitForStarted(2000) || !query.waitForFinished(5000)) {
            query.kill(); query.waitForFinished(1000); return {};
        }
        return query.exitStatus() == QProcess::NormalExit && query.exitCode() == 0
            ? query.readAllStandardOutput() : QByteArray{};
    }
    void inventory() {
        diskChoice->clear(); disks.clear();
        if (preview) disks = {{"/dev/vda", "Preview virtual disk", "252:0", 64ULL * 1024 * 1024 * 1024}};
        else if (live) {
            QString problem;
            disks = eligibleDisks(readOnlyCommand("/usr/bin/lsblk", {"--json", "--bytes", "--output",
                "PATH,TYPE,SIZE,MODEL,RO,MAJ:MIN,MOUNTPOINTS"}), 16ULL * 1024 * 1024 * 1024, &problem);
            if (!problem.isEmpty()) error->setText(problem);
        }
        for (const auto &disk : disks)
            diskChoice->addItem(QString("%1 · %2 GiB · %3").arg(disk.path).arg(disk.bytes / 1073741824.0, 0, 'f', 1).arg(disk.model));
        if (disks.isEmpty()) error->setText("No eligible disk found. Use the UEFI live system, and unmount target filesystems first.");
        updateButtons();
    }
    void updateButtons() {
        if (!next || !confirmation || !password) return;
        back->setEnabled(page > 0 && page < 4 && !running);
        next->setText(page == 3 ? (preview ? "Preview progress" : "Erase disk and install") : page == 5 ? "Close" : "Continue");
        bool allowed = !running && page != 4;
        if (page == 1) allowed = !selectedDisk().path.isEmpty();
        if (page == 2) { error->setText(request().validationError()); allowed = request().validationError().isEmpty(); }
        if (page == 3) allowed = preview || canInstall(request(), selectedDisk(), live, preview,
                                                       acknowledge->isChecked(), confirmation->text());
        next->setEnabled(allowed);
    }
    void showPage(int index) {
        page = index; pages->setCurrentIndex(page); error->clear();
        QStringList labels;
        for (int i = 0; i < steps.size(); ++i) labels << (i == page ? "[ " + steps[i] + " ]" : steps[i]);
        stepLabel->setText(labels.join("   ·   "));
        if (page == 3) {
            const auto disk = selectedDisk();
            review->setText(QString("Erase %1 (%2, %3 GiB)\n\nCreate a 1 GiB EFI partition and an ext4 system partition.\nInstall the live system with systemd-boot.\n\nUser: %4\nComputer: %5\n\nEvery existing file on the selected disk will be lost.")
                .arg(disk.path, disk.model).arg(disk.bytes / 1073741824.0, 0, 'f', 1).arg(user->text(), hostname->text()));
            confirmation->setPlaceholderText("ERASE " + disk.path);
        }
        if (page == 5 && preview) finished->setText("Preview complete. No disks were read or changed, and no installation was performed.");
        if (page == 1 && disks.isEmpty()) error->setText("No eligible disk found. Use the UEFI live system, and unmount target filesystems first.");
        updateButtons();
    }
    void finish(bool success, const QString &message) {
        running = false; credentials.fill('\0'); credentials.clear(); secrets.clear();
        progress->setRange(0, 1); progress->setValue(success ? 1 : 0);
        finished->setText(message); showPage(5); close->setEnabled(true);
    }
    void beginInstall() {
        if (preview) {
            showPage(4); phase->setText("Preview only — no installation commands will run.");
            QTimer::singleShot(1500, this, [this] { finish(true, "Preview complete."); }); return;
        }
        const auto data = request(); const auto disk = selectedDisk();
        if (!canInstall(data, disk, live, preview, acknowledge->isChecked(), confirmation->text())) return;
        QString program = "/usr/bin/yurei-install";
        auto args = backendArguments(data, disk);
#ifdef Q_OS_LINUX
        if (geteuid() != 0) { args.prepend(program); args.prepend("--disable-internal-agent"); program = "/usr/bin/pkexec"; }
#else
        error->setText("Installation requires the Yurei Linux live system."); return;
#endif
        secrets = {data.password, data.rootPassword};
        credentials = data.password.toUtf8() + '\n' + data.rootPassword.toUtf8() + '\n';
        password->clear(); repeat->clear(); rootPassword->clear(); rootRepeat->clear();
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.remove("YUREI_USER_PASSWORD"); environment.remove("YUREI_ROOT_PASSWORD");
        environment.insert("LC_ALL", "C.UTF-8"); process.setProcessEnvironment(environment);
        running = true; showPage(4); close->setEnabled(false);
        phase->setText("Checking the live system and target disk…");
        process.start(program, args);
    }
protected:
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this); QPixmap art(":/yurei/slide-shrine.jpg");
        const auto scaled = art.scaled(size(), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        painter.drawPixmap(width() - scaled.width(), (height() - scaled.height()) / 2, scaled);
        QLinearGradient shade(0, 0, width(), 0);
        shade.setColorAt(0, QColor(6, 12, 31, 250)); shade.setColorAt(.56, QColor(6, 12, 31, 235));
        shade.setColorAt(1, QColor(6, 12, 31, 65)); painter.fillRect(rect(), shade);
    }
    void closeEvent(QCloseEvent *event) override {
        if (running) {
            QMessageBox::warning(this, "Installation is running", "Wait for installation to finish before closing this window.");
            event->ignore();
        } else event->accept();
    }
public:
    explicit Installer(bool isPreview) : preview(isPreview), next(nullptr), confirmation(nullptr), password(nullptr) {
        setWindowTitle("Install Yūrei"); resize(1100, 720); setMinimumSize(960, 680);
        setStyleSheet("QWidget{color:#e6e1ff;font-family:sans-serif;font-size:14px;}"
            "QLineEdit,QComboBox,QPlainTextEdit{background:#111831;border:1px solid #72658e;border-radius:8px;padding:9px;color:#f1e9ff;}"
            "QComboBox QAbstractItemView{background:#111831;color:#f1e9ff;}"
            "QPushButton{background:#b9aaff;color:#060c1f;border:0;border-radius:8px;padding:10px 20px;font-weight:600;}"
            "QPushButton:disabled{background:#454257;color:#aaa4bc;}"
            "QCheckBox{spacing:8px;} QProgressBar{background:#111831;border:1px solid #72658e;border-radius:6px;height:15px;}"
            "QProgressBar::chunk{background:#b9aaff;} QToolTip{background:#111831;color:#f1e9ff;}");
        auto *outer = new QVBoxLayout(this); outer->setContentsMargins(42, 26, 42, 26); outer->setSpacing(16);
        outer->addWidget(text("Yūrei  /  System installation", 19));
        notice = text(preview ? "DESIGN PREVIEW — no disk operations" : "Independent preview · UEFI · whole-disk installation only", 12);
        notice->setStyleSheet("color:#d7caff;font-size:12px;"); outer->addWidget(notice);
        pages = new QStackedWidget; pages->setMaximumWidth(620); outer->addWidget(pages, 1);
        auto *welcome = newPage("Welcome to Yūrei", "Your own gaming-first Linux system, built from source.\n\nThis installer copies the independent live system onto your chosen disk.");
        welcome->addWidget(text("The current preview supports UEFI boot, one ext4 system partition, and systemd-boot. Dual boot, custom partitioning and disk encryption are not available yet.")); welcome->addStretch();
        auto *diskPage = newPage("Choose an installation disk", "The entire selected disk will be erased. Read-only disks, mounted filesystems, and the live medium are excluded. At least 16 GiB is required; the backend checks the actual image size before erasing.");
        diskChoice = new QComboBox; diskPage->addWidget(diskChoice);
        auto *refresh = new QPushButton("Refresh disks"); diskPage->addWidget(refresh, 0, Qt::AlignLeft); diskPage->addStretch();
        connect(refresh, &QPushButton::clicked, this, [this] { inventory(); });
        connect(diskChoice, &QComboBox::currentIndexChanged, this, [this] { acknowledge->setChecked(false); confirmation->clear(); updateButtons(); });
        auto *account = newPage("Make it your system", "Create your login account and computer name. Passwords are passed privately to the installer through standard input.");
        auto *form = new QFormLayout;
        user = field(); hostname = field(); password = field(true); repeat = field(true);
        rootPassword = field(true); rootRepeat = field(true);
        form->addRow("User name", user); form->addRow("Computer name", hostname);
        form->addRow("Password", password); form->addRow("Repeat password", repeat);
        samePassword = new QCheckBox("Use the same password for the administrator account"); samePassword->setChecked(true);
        form->addRow(samePassword); form->addRow("Administrator password", rootPassword); form->addRow("Repeat administrator password", rootRepeat);
        rootPassword->setEnabled(false); rootRepeat->setEnabled(false); account->addLayout(form); account->addStretch();
        connect(samePassword, &QCheckBox::toggled, this, [this](bool same) { rootPassword->setEnabled(!same); rootRepeat->setEnabled(!same); updateButtons(); });
        auto *summary = newPage("Review before installing", "Check the disk and account below. Nothing is changed until you explicitly start installation.");
        review = text(""); summary->addWidget(review);
        acknowledge = new QCheckBox("I have backed up this disk and understand that all its data will be erased."); summary->addWidget(acknowledge);
        confirmation = field(); summary->addWidget(text("Type ERASE followed by the exact disk path:", 13)); summary->addWidget(confirmation); summary->addStretch();
        connect(acknowledge, &QCheckBox::toggled, this, [this] { updateButtons(); });
        auto *install = newPage("Installing Yūrei", "Keep the computer connected to power. Do not remove the live medium while installation is running.");
        phase = text("Preparing…"); install->addWidget(phase); progress = new QProgressBar; progress->setRange(0, 0); install->addWidget(progress);
        log = new QPlainTextEdit; log->setReadOnly(true); log->setMaximumBlockCount(1000); install->addWidget(log, 1);
        auto *done = newPage("Installation result", ""); finished = text("The installer has not run.", 18); done->addWidget(finished);
        auto *details = new QPushButton("View installation output"); done->addWidget(details, 0, Qt::AlignLeft); done->addStretch();
        connect(details, &QPushButton::clicked, this, [this] {
            QMessageBox box(QMessageBox::Information, "Installer output", "Installation output (expand details to view).", QMessageBox::Close, this);
            box.setDetailedText(log->toPlainText()); box.exec();
        });
        error = text("", 13); error->setStyleSheet("color:#ffb3ca;font-size:13px;"); outer->addWidget(error);
        stepLabel = text("", 12); outer->addWidget(stepLabel);
        auto *navigation = new QHBoxLayout; close = new QPushButton("Close"); back = new QPushButton("Back"); next = new QPushButton("Continue");
        navigation->addWidget(close); navigation->addStretch(); navigation->addWidget(back); navigation->addWidget(next); outer->addLayout(navigation);
        connect(close, &QPushButton::clicked, this, &QWidget::close);
        connect(back, &QPushButton::clicked, this, [this] { showPage(page - 1); });
        connect(next, &QPushButton::clicked, this, [this] {
            if (page == 5) { QWidget::close(); return; }
            if (page == 3) { beginInstall(); return; }
            if (page == 2 && !request().validationError().isEmpty()) { error->setText(request().validationError()); return; }
            showPage(page + 1);
        });
        process.setProcessChannelMode(QProcess::MergedChannels);
        connect(&process, &QProcess::started, this, [this] { process.write(credentials); process.closeWriteChannel(); credentials.fill('\0'); credentials.clear(); });
        connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
            QString output = QString::fromUtf8(process.readAllStandardOutput());
            for (const auto &secret : secrets) if (!secret.isEmpty()) output.replace(secret, "[redacted]");
            log->appendPlainText(output.trimmed());
            for (const auto &line : output.split('\n')) if (line.startsWith("== ")) phase->setText(line.mid(3).trimmed());
        });
        connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError problem) {
            if (problem == QProcess::FailedToStart) finish(false, "The installer could not start. No installation command was launched.");
        });
        connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            const bool success = status == QProcess::NormalExit && code == 0;
            finish(success, success ? "Yūrei is installed. Close this window, shut down, remove the USB stick, and start the computer again."
                : "Installation did not finish. The target disk may be partially changed. Review the installer output; do not assume it is bootable.");
        });
        if (preview) { user->setText("yurei"); hostname->setText("yurei-pc"); password->setText("preview-only"); repeat->setText("preview-only"); }
#ifdef Q_OS_LINUX
        if (!preview && QFileInfo::exists("/sys/firmware/efi") && QFileInfo("/usr/bin/yurei-install").isExecutable()) {
            QProcess probe; probe.start("/usr/bin/mountpoint", {"-q", "/run/live/rootfs"});
            if (probe.waitForStarted(1000) && probe.waitForFinished(2000)) live = probe.exitCode() == 0;
            else { probe.kill(); probe.waitForFinished(1000); }
        }
#endif
        if (!preview && !live) notice->setText("Installation is unavailable here. Start Yūrei's UEFI live system, or use --preview to explore the design.");
        inventory(); showPage(0);
    }
    void previewPage(int index) { if (preview) showPage(qBound(0, index, 5)); }
};

int main(int argc, char **argv) {
    QApplication app(argc, argv); app.setApplicationName("yurei-install-gui");
    QCommandLineParser parser; parser.addHelpOption();
    parser.addOption({"preview", "Explore the design without disk discovery or installation."});
    parser.addOption({"screenshot", "Save a preview screenshot and exit (requires --preview).", "file"});
    parser.addOption({"page", "Preview page: 0 welcome, 1 disk, 2 account, 3 review, 4 progress, 5 finish.", "number", "0"});
    parser.process(app);
    if (parser.isSet("screenshot") && !parser.isSet("preview")) parser.showHelp(2);
    Installer window(parser.isSet("preview")); window.previewPage(parser.value("page").toInt()); window.show();
    if (parser.isSet("screenshot")) QTimer::singleShot(500, &window, [&] { app.exit(window.grab().save(parser.value("screenshot")) ? 0 : 1); });
    return app.exec();
}
