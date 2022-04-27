//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

class LibraryViewController: MangaCollectionViewController {

    var unfilteredManga: [Manga] = [] {
        didSet {
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
            }
        }
    }

    var unfilteredPinnedManga: [Manga] = [] {
        didSet {
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty || !self.unfilteredPinnedManga.isEmpty
            }
        }
    }

    override var manga: [Manga] {
        get {
            unfilteredManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredManga = newValue
        }
    }

    override var pinnedManga: [Manga] {
        get {
            unfilteredPinnedManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredPinnedManga = newValue
        }
    }

    var readHistory: [String: [String: Int]] = [:]
    var opensReaderView = false
    var preloadsChapters = false

    var searchText: String = ""
    var updatedLibrary = false

    let emptyTextStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LIBRARY", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH", comment: "")
        navigationItem.searchController = searchController

        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        preloadsChapters = true
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

//        collectionView?.register(MangaListSelectionHeader.self,
//                                 forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
//                                 withReuseIdentifier: "MangaListSelectionHeader")

        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .equalSpacing
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center

        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = NSLocalizedString("LIBRARY_EMPTY", comment: "")
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)

        let emptyTextLabel = UILabel()
        emptyTextLabel.text = NSLocalizedString("LIBRARY_ADD_FROM_BROWSE", comment: "")
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTextLabel)

        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)

        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        NotificationCenter.default.addObserver(forName: Notification.Name("Library.pinManga"), object: nil, queue: nil) { _ in
            self.fetchLibrary()
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("updateLibrary"), object: nil, queue: nil) { _ in
            let previousManga = self.manga
            let previousPinnedManga = self.pinnedManga

            Task { @MainActor in
                var reordered = false
                await self.loadChaptersAndHistory()

                if self.collectionView?.numberOfSections == 1 && !self.pinnedManga.isEmpty { // insert pinned section
                    self.collectionView?.performBatchUpdates {
                        self.collectionView?.insertSections(IndexSet(integer: 0))
                    }
                } else if self.collectionView?.numberOfSections == 2 && self.pinnedManga.isEmpty { // remove pinned section
                    self.collectionView?.performBatchUpdates {
                        self.collectionView?.deleteSections(IndexSet(integer: 0))
                    }
                }

                if !self.pinnedManga.isEmpty && self.pinnedManga.count == previousPinnedManga.count {
                    self.collectionView?.performBatchUpdates {
                        for (i, manga) in previousPinnedManga.enumerated() {
                            let from = IndexPath(row: i, section: 0)
                            if let j = self.pinnedManga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }),
                               j != i {
                                let to = IndexPath(row: j, section: 0)
                                self.collectionView?.moveItem(at: from, to: to)
                            }
                        }

                        reordered = true
                    }
                }

                if !self.manga.isEmpty && self.manga.count == previousManga.count { // reorder
                    self.collectionView?.performBatchUpdates {
                        for (i, manga) in previousManga.enumerated() {
                            let from = IndexPath(row: i, section: self.pinnedManga.isEmpty ? 0 : 1)
                            if let j = self.manga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }),
                               j != i {
                                let to = IndexPath(row: j, section: self.pinnedManga.isEmpty ? 0 : 1)
                                self.collectionView?.moveItem(at: from, to: to)
                            }
                        }

                        reordered = true
                    }
                }

                if !reordered {
                    self.collectionView?.reloadData()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

        super.viewWillAppear(animated)

        fetchLibrary()

        if !updatedLibrary {
            updatedLibrary = true
            Task {
                await DataManager.shared.updateLibrary()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh), for: .valueChanged)
        collectionView?.refreshControl = refreshControl

        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func fetchLibrary() {
        Task {
            await loadChaptersAndHistory()
            reloadData()
        }
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl) {
        Task {
            await DataManager.shared.updateLibrary()
            refreshControl.endRefreshing()
        }
    }

    func loadChaptersAndHistory() async {
        var tempManga: [Manga] = []
        var tempPinnedManga: [Manga] = []

        if opensReaderView || preloadsChapters || badgeType == .unread {
            var i = 0
            for m in DataManager.shared.libraryManga {
                let mangaId = "\(m.sourceId).\(m.id)"

                if opensReaderView {
                    readHistory[mangaId] = DataManager.shared.getReadHistory(manga: m)
                }

                chapters[mangaId] = await DataManager.shared.getChapters(for: m)

                if badgeType == .unread {
                    if preloadsChapters {
                        readHistory[mangaId] = DataManager.shared.getReadHistory(manga: m)
                    }

                    let badgeNum = (chapters[mangaId]?.count ?? 0) - (readHistory[mangaId]?.count ?? 0)
                    badges[mangaId] = badgeNum

                    let pinManga = UserDefaults.standard.bool(forKey: "Library.pinManga")
                    let pinType = UserDefaults.standard.integer(forKey: "Library.pinMangaType")

                    if badgeNum > 0 {
                        if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                            cell.badgeNumber = badges[mangaId]
                        }
                        if pinManga && (pinType == 0 || (pinType == 1 && m.lastUpdated ?? Date.distantPast > m.lastOpened ?? Date.distantPast)) {
                            tempPinnedManga.append(m)
                            i += 1
                        } else {
                            tempManga.append(m)
                        }
                    } else if pinManga && pinType == 1 && m.lastUpdated ?? Date.distantPast > m.lastOpened ?? Date.distantFuture {
                        tempPinnedManga.append(m)
                        i += 1
                    } else {
                        tempManga.append(m)
                    }
                    if !pinManga {
                        i += 1
                    }
                }
            }
        } else {
            chapters = [:]
            readHistory = [:]
        }

        manga = tempManga
        pinnedManga = tempPinnedManga
    }

    func getNextChapter(for manga: Manga) -> Chapter? {
        let mangaId = "\(manga.sourceId).\(manga.id)"
        let id = readHistory[mangaId]?.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters[mangaId]?.first { $0.id == id }
        }
        return chapters[mangaId]?.last
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController: UICollectionViewDelegateFlowLayout {

//    func collectionView(_ collectionView: UICollectionView,
//                        layout collectionViewLayout: UICollectionViewLayout,
//                        referenceSizeForHeaderInSection section: Int) -> CGSize {
//        CGSize(width: collectionView.bounds.width, height: 40)
//    }
//
//    func collectionView(_ collectionView: UICollectionView,
//                        viewForSupplementaryElementOfKind kind: String,
//                        at indexPath: IndexPath) -> UICollectionReusableView {
//        if kind == UICollectionView.elementKindSectionHeader {
//            var header = collectionView.dequeueReusableSupplementaryView(
//                ofKind: kind,
//                withReuseIdentifier: "MangaListSelectionHeader",
//                for: indexPath
//            ) as? MangaListSelectionHeader
//            if header == nil {
//                header = MangaListSelectionHeader(frame: .zero)
//            }
//            header?.delegate = nil
//            header?.options = ["Default"]
//            header?.selectedOption = 0
//            header?.delegate = self
//            return header ?? UICollectionReusableView()
//        }
//        return UICollectionReusableView()
//    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let targetManga: Manga
        if indexPath.section == 0 && !pinnedManga.isEmpty {
            guard pinnedManga.count > indexPath.row else { return }
            targetManga = pinnedManga[indexPath.row]
        } else {
            guard manga.count > indexPath.row else { return }
            targetManga = manga[indexPath.row]
        }
        if opensReaderView,
           let chapter = getNextChapter(for: targetManga),
           SourceManager.shared.source(for: targetManga.sourceId) != nil {
            let readerController = ReaderViewController(
                manga: targetManga,
                chapter: chapter,
                chapterList: chapters["\(targetManga.sourceId).\(targetManga.id)"] ?? []
            )
            let navigationController = ReaderNavigationController(rootViewController: readerController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } else {
            openMangaView(for: targetManga)
        }
        DataManager.shared.setOpened(manga: targetManga)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let targetManga: Manga
        if indexPath.section == 0 && !self.pinnedManga.isEmpty {
            guard self.pinnedManga.count > indexPath.row else { return nil }
            targetManga = self.pinnedManga[indexPath.row]
        } else {
            guard self.manga.count > indexPath.row else { return nil }
            targetManga = self.manga[indexPath.row]
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            var actions: [UIAction] = []

            if DataManager.shared.libraryContains(manga: targetManga) {
                actions.append(UIAction(title: NSLocalizedString("REMOVE_FROM_LIBRARY", comment: ""),
                                        image: UIImage(systemName: "trash")) { _ in
                    DataManager.shared.delete(manga: targetManga)
                })
            } else {
                actions.append(UIAction(title: NSLocalizedString("ADD_TO_LIBRARY", comment: ""),
                                        image: UIImage(systemName: "books.vertical.fill")) { _ in
                    Task { @MainActor in
                        if let newManga = try? await SourceManager.shared.source(for: targetManga.sourceId)?.getMangaDetails(manga: targetManga) {
                            _ = DataManager.shared.addToLibrary(manga: newManga)
                        }
                    }
                })
            }
            if self.opensReaderView {
                actions.append(UIAction(title: NSLocalizedString("MANGA_INFO", comment: ""), image: UIImage(systemName: "info.circle")) { _ in
                    self.openMangaView(for: targetManga)
                })
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        fetchLibrary()
    }
}

// MARK: - Search Results Updater
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        collectionView?.reloadData()
    }
}
