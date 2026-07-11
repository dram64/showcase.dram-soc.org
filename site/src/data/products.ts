export type Product = {
  slug: string;
  title: string;
  price: number;
  category: "deskmat" | "print" | "tapestry" | "sticker" | "flag" | "tote" | "lanyard";
  image: string;
  soldOut?: boolean;
  lowStock?: number;
};

export const products: Product[] = [
  // Deskmats
  { slug: "deskmat-yuzuha-alice", title: "Yuzuha & Alice Deskmat", price: 25, category: "deskmat", image: "/assets/YuzuhaAliceDeskmat.webp" },
  { slug: "deskmat-toki-bunny", title: "Toki Bunny Deskmat", price: 25, category: "deskmat", image: "/assets/TokiBunnyDeskmat.webp", lowStock: 2 },
  { slug: "deskmat-jane-doe", title: "Jane Doe Deskmat", price: 25, category: "deskmat", image: "/assets/JaneDoeDeskmat.webp", lowStock: 2 },
  { slug: "deskmat-yi-xuan", title: "Yi Xuan Deskmat", price: 25, category: "deskmat", image: "/assets/YiXuanDeskmat.webp", lowStock: 1 },
  { slug: "deskmat-ironmouse", title: "Ironmouse Deskmat", price: 25, category: "deskmat", image: "/assets/IronmouseDeskmat.webp", lowStock: 1 },
  { slug: "deskmat-topaz", title: "Topaz Deskmat", price: 25, category: "deskmat", image: "/assets/TopazDeskmat.webp" },
  { slug: "deskmat-wanderer", title: "Wanderer Deskmat", price: 25, category: "deskmat", image: "/assets/WandererDeskmat.webp" },
  { slug: "deskmat-fuwamoco", title: "Fuwamoco Deskmat", price: 25, category: "deskmat", image: "/assets/FuwamocoDeskmat.webp", soldOut: true },
  { slug: "deskmat-ayaka", title: "Ayaka Dodgers Deskmat", price: 25, category: "deskmat", image: "/assets/AyakaDodgersDeskmat.webp", soldOut: true },

  // Tapestries
  { slug: "tapestry-astra-yao", title: "Astra Yao Tapestry", price: 25, category: "tapestry", image: "/assets/AstraYao.webp", lowStock: 1 },
  { slug: "tapestry-jane-doe", title: "Jane Doe Tapestry", price: 25, category: "tapestry", image: "/assets/JaneDoeTapestry.webp", lowStock: 1 },
  { slug: "tapestry-yi-xuan", title: "Yi Xuan Tapestry", price: 25, category: "tapestry", image: "/assets/YiXuanTapestry.webp", lowStock: 1 },
  { slug: "tapestry-citlali", title: "Citlali Tapestry", price: 25, category: "tapestry", image: "/assets/CitlaliTapestry.webp", lowStock: 1 },
  { slug: "tapestry-wanderer", title: "Wanderer Tapestry", price: 25, category: "tapestry", image: "/assets/WandererTapestry.webp" },
  { slug: "tapestry-ayaka", title: "Ayaka Tapestry", price: 25, category: "tapestry", image: "/assets/AyakaTapestry.webp", soldOut: true },

  // Prints
  { slug: "print-yuzuha", title: "Yuzuha Print", price: 5, category: "print", image: "/assets/YuzuhaPrint.webp" },
  { slug: "print-alice", title: "Alice Print", price: 5, category: "print", image: "/assets/AlicePrint.webp" },
  { slug: "print-castorice", title: "Castorice Print", price: 5, category: "print", image: "/assets/Castorice.webp" },
  { slug: "print-faruzan-maid", title: "Faruzan Maid Print", price: 5, category: "print", image: "/assets/FaruzanMaidPrint.webp" },
  { slug: "print-wanderer", title: "Wanderer Print", price: 5, category: "print", image: "/assets/WandererPrintV2.webp" },
  { slug: "print-cinna-miku", title: "Cinna Miku Print", price: 5, category: "print", image: "/assets/CinnaMikuPrint.webp" },

  // Stickers
  { slug: "sticker-yuzuha", title: "Yuzuha Sticker", price: 3, category: "sticker", image: "/assets/YuzuhaSticker.webp" },
  { slug: "sticker-alice", title: "Alice Sticker", price: 3, category: "sticker", image: "/assets/AliceSticker.webp" },
  { slug: "sticker-jane-doe", title: "Jane Doe Sticker", price: 3, category: "sticker", image: "/assets/JaneDoeSticker.webp" },
  { slug: "sticker-yi-xuan", title: "Yi Xuan Sticker", price: 3, category: "sticker", image: "/assets/YiXuanSticker.webp" },
  { slug: "sticker-blanc-bunny", title: "Blanc Bunny Sticker", price: 3, category: "sticker", image: "/assets/BlancBunny.webp" },
  { slug: "sticker-toki-bunny", title: "Toki Bunny Sticker", price: 3, category: "sticker", image: "/assets/TokiBunnySFW.webp" },
  { slug: "sticker-cipher", title: "Cipher Sticker", price: 3, category: "sticker", image: "/assets/CipherSticker.webp", soldOut: true },
  { slug: "sticker-faruzan", title: "Faruzan Sticker", price: 3, category: "sticker", image: "/assets/FaruzanSticker.webp", soldOut: true },

  // Flags
  { slug: "flag-gigi", title: "Gigi Flag", price: 20, category: "flag", image: "/assets/Gigi.webp" },
  { slug: "flag-ironmouse", title: "Ironmouse Flag", price: 20, category: "flag", image: "/assets/Ironmouse.webp" },

  // PSG drop
  { slug: "psg-deskmat",           title: "PSG Deskmat",             price: 25, category: "deskmat",  image: "/assets/psg-deskmat.webp" },
  { slug: "psg-panty-tapestry",    title: "Panty Tapestry",          price: 25, category: "tapestry", image: "/assets/psg-panty-tapestry.webp" },
  { slug: "psg-stocking-tapestry", title: "Stocking Tapestry",       price: 25, category: "tapestry", image: "/assets/psg-stocking-tapestry.webp" },
  { slug: "psg-panty-acrylic",     title: "Panty Acrylic Stand",     price: 12, category: "print",    image: "/assets/psg-panty-acrylic.webp" },
  { slug: "psg-stocking-acrylic",  title: "Stocking Acrylic Stand",  price: 12, category: "print",    image: "/assets/psg-stocking-acrylic.webp" },
  { slug: "psg-print",             title: "PSG Print",               price: 5,  category: "print",    image: "/assets/psg-print.webp" },
  { slug: "psg-panty-sticker",     title: "Panty Sticker",           price: 3,  category: "sticker",  image: "/assets/psg-panty-sticker.webp" },
  { slug: "psg-stocking-sticker",  title: "Stocking Sticker",        price: 3,  category: "sticker",  image: "/assets/psg-stocking-sticker.webp" },
  { slug: "psg-tote",              title: "PSG Tote Bag",            price: 20, category: "tote",     image: "/assets/psg-tote.webp" },
  { slug: "psg-lanyard",           title: "PSG Lanyard",             price: 10, category: "lanyard",  image: "/assets/psg-lanyard.webp" },

  // NSO drop
  { slug: "nso-deskmat",           title: "NSO Deskmat",             price: 25, category: "deskmat",  image: "/assets/nso-deskmat.webp" },
  { slug: "nso-ame-tapestry",      title: "Ame Tapestry",            price: 25, category: "tapestry", image: "/assets/nso-ame-tapestry.webp" },
  { slug: "nso-kangel-tapestry",   title: "K.Angel Tapestry",        price: 25, category: "tapestry", image: "/assets/nso-kangel-tapestry.webp" },
  { slug: "nso-print",             title: "NSO Print",               price: 5,  category: "print",    image: "/assets/nso-print.webp" },
  { slug: "nso-ame-sticker",       title: "Ame Sticker",             price: 3,  category: "sticker",  image: "/assets/nso-ame-sticker.webp" },
  { slug: "nso-kangel-sticker",    title: "K.Angel Sticker",         price: 3,  category: "sticker",  image: "/assets/nso-kangel-sticker.webp" },
];

export const categories = [
  { key: "deskmat",  title: "Deskmats",  tagline: "900×400mm, 5mm rubber base, sublimated print." },
  { key: "tapestry", title: "Tapestries", tagline: "60×90cm polyester wall scrolls, rod hung." },
  { key: "tote",     title: "Totes",      tagline: "Heavyweight cotton, screen-printed, 15\"×16\"." },
  { key: "lanyard",  title: "Lanyards",   tagline: "Woven polyester, 20mm, metal breakaway clasp." },
  { key: "print",    title: "Prints",     tagline: "12×18\" heavy satin card stock, 300 DPI." },
  { key: "sticker",  title: "Stickers",   tagline: "Die-cut vinyl, weatherproof, laminated." },
  { key: "flag",     title: "Flags",      tagline: "100×100cm polyester, 4-grommet corners." },
] as const;
